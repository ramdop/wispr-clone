import Foundation
import Combine

/// A learned dictionary entry with evidence tracking
struct LearnedEntry: Codable, Identifiable {
    var id: String { canonical }
    let canonical: String           // The correct form (e.g., "Aadhar")
    var aliases: Set<String>        // Incorrect forms (e.g., ["order", "Order"])
    var count: Int                  // How many times this correction was seen
    var lastUpdated: Date
    var bundleID: String?           // Optional app scope (nil = global)
}

/// Evidence for a candidate correction (not yet promoted)
struct CorrectionEvidence: Codable {
    let from: String
    let to: String
    var count: Int
    var lastSeen: Date
    var bundleID: String?
}

/// Store for learned dictionary with evidence tracking
class LearnedDictionaryStore: ObservableObject {
    @Published var entries: [LearnedEntry] = []
    @Published var candidates: [CorrectionEvidence] = []
    
    /// Callback when a new entry is promoted (for user notification)
    var onEntryPromoted: ((LearnedEntry) -> Void)?
    
    private let promotionThreshold = 2  // Promote after 2 occurrences
    private let fileManager = FileManager.default
    
    var entriesUrl: URL {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let directory = appSupport.appendingPathComponent("WisprClone", isDirectory: true)
        if !fileManager.fileExists(atPath: directory.path) {
            try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        return directory.appendingPathComponent("learned_dictionary.json")
    }
    
    private var candidatesUrl: URL {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let directory = appSupport.appendingPathComponent("WisprClone", isDirectory: true)
        return directory.appendingPathComponent("correction_candidates.json")
    }
    
    init() {
        load()
    }
    
    // MARK: - Persistence
    
    func load() {
        // Load entries
        if fileManager.fileExists(atPath: entriesUrl.path) {
            do {
                let data = try Data(contentsOf: entriesUrl)
                // Decode
                var rawEntries = try JSONDecoder().decode([LearnedEntry].self, from: data)
                
                // Cleanup: Remove any entries that are now in STOP_WORDS (e.g., "other" -> "aadhar")
                let initialCount = rawEntries.count
                rawEntries.removeAll { entry in
                    CorrectionDiff.STOP_WORDS.contains(entry.canonical.lowercased())
                }
                
                if rawEntries.count < initialCount {
                    Logger.info("Removed \(initialCount - rawEntries.count) stopword entries (cleanup)")
                    // We should save this cleaned state eventually, but for now we just don't load them.
                    // To be safe, let's mark self.entries as the cleaned list, and the next save will persist it.
                }
                
                self.entries = rawEntries
                Logger.info("Loaded \(entries.count) learned entries")
            } catch {
                Logger.info("Failed to load learned entries: \(error.localizedDescription)")
            }
        } else {
            Logger.info("No learned dictionary file found at \(entriesUrl.path)")
        }
        
        // Load candidates
        if fileManager.fileExists(atPath: candidatesUrl.path) {
            do {
                let data = try Data(contentsOf: candidatesUrl)
                candidates = try JSONDecoder().decode([CorrectionEvidence].self, from: data)
                Logger.info("Loaded \(candidates.count) correction candidates")
            } catch {
                Logger.info("Failed to load correction candidates: \(error.localizedDescription)")
            }
        } else {
            Logger.info("No correction candidates file found at \(candidatesUrl.path)")
        }
    }
    
    func save() {
        // Save entries
        do {
            let data = try JSONEncoder().encode(entries)
            try data.write(to: entriesUrl)
            Logger.debug("Saved \(entries.count) learned entries to \(entriesUrl.path)")
        } catch {
            Logger.error("Failed to save learned entries: \(error.localizedDescription)")
        }
        
        // Save candidates
        do {
            let data = try JSONEncoder().encode(candidates)
            try data.write(to: candidatesUrl)
        } catch {
            Logger.error("[LearnedDictionaryStore] Failed to save candidates: \(error)")
        }
    }
    
    // MARK: - Evidence Tracking
    
    /// Record a correction candidate. May promote to dictionary if threshold reached.
    func recordCorrection(_ candidate: ReplacementCandidate, bundleID: String?) {
        let from = candidate.from.lowercased()
        let to = candidate.to
        
        // Check if already in entries (update alias)
        if let idx = entries.firstIndex(where: { $0.canonical.lowercased() == to.lowercased() }) {
            entries[idx].aliases.insert(from)
            entries[idx].count += 1
            entries[idx].lastUpdated = Date()
            save()
            Logger.debug("[LearnedDictionaryStore] Updated existing entry: '\(from)' → '\(to)'")
            return
        }
        
        // Check if candidate exists with same FROM and TO word
        if let idx = candidates.firstIndex(where: { $0.from.lowercased() == from && $0.to == to }) {
            candidates[idx].count += 1
            candidates[idx].lastSeen = Date()
            Logger.debug("[LearnedDictionaryStore] Candidate count incremented: '\(from)' → '\(to)' (count: \(candidates[idx].count))")
            
            // Check for promotion
            if candidates[idx].count >= promotionThreshold {
                promoteCandidateDirectly(candidates[idx])
                candidates.remove(at: idx) // Remove this specific candidate after promotion
            }
            save()
        } else {
            // Add new candidate
            let evidence = CorrectionEvidence(
                from: from,
                to: to,
                count: 1,
                lastSeen: Date(),
                bundleID: bundleID
            )
            candidates.append(evidence)
            save()
            Logger.debug("[LearnedDictionaryStore] New candidate recorded: '\(from)' → '\(to)'")
        }
    }
    
    private func promoteWithAliases(canonical: String, aliases: Set<String>, bundleID: String?) {
        let entry = LearnedEntry(
            canonical: canonical,
            aliases: aliases,
            count: aliases.count,
            lastUpdated: Date(),
            bundleID: bundleID
        )
        entries.append(entry)
        save()
        
        let aliasesArray = Array(aliases)
        Logger.info("[LearnedDictionaryStore] Promoted to dictionary: \(aliasesArray) → '\(canonical)'")
        
        // Notify for user feedback
        onEntryPromoted?(entry)
    }
    
    private func promoteCandidateDirectly(_ evidence: CorrectionEvidence) {
        let entry = LearnedEntry(
            canonical: evidence.to,
            aliases: [evidence.from.lowercased()],
            count: evidence.count,
            lastUpdated: Date(),
            bundleID: evidence.bundleID
        )
        entries.append(entry)
        save()
        
        Logger.info("[LearnedDictionaryStore] Promoted to dictionary (direct): '\(evidence.from)' → '\(evidence.to)'")
        
        // Notify for user feedback
        onEntryPromoted?(entry)
    }
    
    // MARK: - Dictionary Application
    
    /// Apply learned dictionary replacements to text (pre-paste)
    func applyReplacements(to text: String) -> String {
        var result = text
        
        for entry in entries {
            for alias in entry.aliases {
                // Word-boundary aware, case-insensitive replacement
                let pattern = "\\b\(NSRegularExpression.escapedPattern(for: alias))\\b"
                if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                    let range = NSRange(result.startIndex..<result.endIndex, in: result)
                    result = regex.stringByReplacingMatches(in: result, options: [], range: range, withTemplate: entry.canonical)
                }
            }
        }
        
        return result
    }
    
    // MARK: - Manual Management
    
    func removeEntry(_ entry: LearnedEntry) {
        entries.removeAll { $0.id == entry.id }
        save()
    }
    
    func clearCandidates() {
        candidates.removeAll()
        save()
    }
}
