import Foundation

@MainActor
class ModelDownloader: NSObject, ObservableObject, URLSessionDownloadDelegate {
    @Published var progress: Double = 0.0
    @Published var isDownloading: Bool = false
    
    private var session: URLSession!
    private var continuation: CheckedContinuation<URL, Error>?
    
    override init() {
        super.init()
        self.session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
    }
    
    func download(from url: URL) async throws -> URL {
        guard !isDownloading else {
            throw NSError(domain: "ModelDownloader", code: 1, userInfo: [NSLocalizedDescriptionKey: "Download already in progress"])
        }
        
        isDownloading = true
        progress = 0.0
        
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            let task = session.downloadTask(with: url)
            task.resume()
        }
    }
    
    // MARK: - URLSessionDownloadDelegate
    
    nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        let progress = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        
        Task { @MainActor in
            self.progress = progress
        }
    }
    
    nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        // Move to temporary location that persists after function returns
        let tempDir = FileManager.default.temporaryDirectory
        let tempDst = tempDir.appendingPathComponent(UUID().uuidString).appendingPathExtension("bin")
        
        do {
            try FileManager.default.moveItem(at: location, to: tempDst)
            
            Task { @MainActor in
                self.isDownloading = false
                self.progress = 1.0
                self.continuation?.resume(returning: tempDst)
                self.continuation = nil
            }
        } catch {
            Task { @MainActor in
                self.isDownloading = false
                self.continuation?.resume(throwing: error)
                self.continuation = nil
            }
        }
    }
    
    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error {
            Task { @MainActor in
                self.isDownloading = false
                self.continuation?.resume(throwing: error)
                self.continuation = nil
            }
        }
    }
}
