import Foundation

/// Runs `operation`, but gives up after `seconds`.
///
/// A task group can't be used for this: it always waits for every child task to finish,
/// even after `cancelAll()` or a thrown error. An operation that ignores cancellation
/// (a blocked AX call, a callback that never fires) would hold the group open long after
/// the "timeout". Here the caller resumes as soon as the deadline passes; the operation is
/// cancelled and left to wind down on its own.
func withTimeout<T: Sendable>(
    seconds: TimeInterval,
    timeoutError: @escaping @Sendable () -> Error,
    operation: @escaping @Sendable () async throws -> T
) async throws -> T {
    let race = TimeoutRace<T>()
    return try await withTaskCancellationHandler {
        try await withCheckedThrowingContinuation { continuation in
            race.start(continuation: continuation, seconds: seconds, timeoutError: timeoutError, operation: operation)
        }
    } onCancel: {
        race.finish(.failure(CancellationError()))
    }
}

/// Resumes the continuation exactly once, with whichever of work / deadline / cancellation comes first.
private final class TimeoutRace<T: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<T, Error>?
    private var tasks: [Task<Void, Never>] = []
    private var finished = false

    func start(continuation: CheckedContinuation<T, Error>,
               seconds: TimeInterval,
               timeoutError: @escaping @Sendable () -> Error,
               operation: @escaping @Sendable () async throws -> T) {
        lock.lock()
        if finished {
            // Cancelled before we started
            lock.unlock()
            continuation.resume(throwing: CancellationError())
            return
        }
        self.continuation = continuation
        lock.unlock()

        let work = Task {
            do {
                self.finish(.success(try await operation()))
            } catch {
                self.finish(.failure(error))
            }
        }
        let timer = Task {
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            if !Task.isCancelled {
                self.finish(.failure(timeoutError()))
            }
        }

        lock.lock()
        if finished {
            lock.unlock()
            work.cancel()
            timer.cancel()
            return
        }
        tasks = [work, timer]
        lock.unlock()
    }

    func finish(_ result: Result<T, Error>) {
        lock.lock()
        if finished {
            lock.unlock()
            return
        }
        finished = true
        let continuation = self.continuation
        self.continuation = nil
        let tasks = self.tasks
        self.tasks = []
        lock.unlock()

        tasks.forEach { $0.cancel() }
        continuation?.resume(with: result)
    }
}
