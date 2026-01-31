import Foundation
import Combine

class SnippetStore: ObservableObject {
    @Published var snippets: [Snippet] = []
    
    private let fileManager = FileManager.default
    private var saveUrl: URL {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let directory = appSupport.appendingPathComponent("WisprClone", isDirectory: true)
        
        // Ensure directory exists
        if !fileManager.fileExists(atPath: directory.path) {
            try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        
        return directory.appendingPathComponent("snippets.json")
    }
    
    init() {
        load()
    }
    
    func load() {
        guard fileManager.fileExists(atPath: saveUrl.path) else {
            // Load defaults if no file exists
            self.snippets = [
                Snippet(trigger: "scheduling link", expansion: "You can book a time with me here: https://calendly.com/wispr-flow/intro"),
                Snippet(trigger: "github repo", expansion: "https://github.com/wispr-ai/flow")
            ]
            save()
            return
        }
        
        do {
            let data = try Data(contentsOf: saveUrl)
            self.snippets = try JSONDecoder().decode([Snippet].self, from: data)
            Logger.info("Loaded \(snippets.count) snippets")
        } catch {
            Logger.info("No snippets file found (or load failed)")
        }
    }
    
    func save() {
        do {
            let data = try JSONEncoder().encode(snippets)
            try data.write(to: saveUrl)
            Logger.debug("Saved snippets to \(saveUrl.path)")
        } catch {
            Logger.error("Failed to save snippets: \(error)")
        }
    }
    
    func addSnippet(trigger: String, expansion: String) {
        let trimmedTrigger = trigger.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTrigger.isEmpty else { return }
        
        let newSnippet = Snippet(trigger: trimmedTrigger, expansion: expansion)
        snippets.append(newSnippet)
        save()
    }
    
    func deleteSnippet(at offsets: IndexSet) {
        snippets.remove(atOffsets: offsets)
        save()
    }
    
    func updateSnippet(_ snippet: Snippet) {
        if let index = snippets.firstIndex(where: { $0.id == snippet.id }) {
            snippets[index] = snippet
            save()
        }
    }
    
    /// Expands triggers found in the input text using exact (case-insensitive) matching.
    func expandTriggers(in text: String) -> String {
        var result = text
        
        // Sort snippets by trigger length descending to match longer phrases first
        let sortedSnippets = snippets.sorted { $0.trigger.count > $1.trigger.count }
        
        for snippet in sortedSnippets {
            let trigger = snippet.trigger
            // Case-insensitive exact match for the whole trigger phrase
            // We use NSRegularExpression to find all occurrences with word boundaries
            let pattern = "\\b\(NSRegularExpression.escapedPattern(for: trigger))\\b"
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                let range = NSRange(result.startIndex..<result.endIndex, in: result)
                result = regex.stringByReplacingMatches(in: result, options: [], range: range, withTemplate: snippet.expansion)
            }
        }
        
        return result
    }
}
