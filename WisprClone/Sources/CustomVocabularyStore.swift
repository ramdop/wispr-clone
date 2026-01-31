import Foundation
import Combine

class CustomVocabularyStore: ObservableObject {
    @Published var words: [String] = []
    
    private let fileManager = FileManager.default
    private var saveUrl: URL {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let directory = appSupport.appendingPathComponent("WisprClone", isDirectory: true)
        
        // Ensure directory exists
        if !fileManager.fileExists(atPath: directory.path) {
            try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        
        return directory.appendingPathComponent("custom_vocabulary.json")
    }
    
    init() {
        load()
    }
    
    func load() {
        guard fileManager.fileExists(atPath: saveUrl.path) else {
            // Default words if no file exists
            self.words = ["Wispr", "Wispr Flow", "Vipah Loan"]
            save()
            return
        }
        
        do {
            let data = try Data(contentsOf: saveUrl)
            let loaded = try JSONDecoder().decode([String].self, from: data)
            self.words = loaded
            Logger.info("Loaded \(loaded.count) custom words")
        } catch {
            Logger.info("No custom vocabulary found (or load failed)")
        }
    }
    
    func save() {
        do {
            let data = try JSONEncoder().encode(words)
            try data.write(to: saveUrl)
        } catch {
            Logger.info("Failed to save custom vocabulary: \(error)")
        }
    }
    
    func addWord(_ word: String) {
        let trimmed = word.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !words.contains(trimmed) else { return }
        
        words.append(trimmed)
        save()
    }
    
    func removeWord(_ word: String) {
        words.removeAll { $0 == word }
        save()
    }
    
    func deleteWords(at offsets: IndexSet) {
        words.remove(atOffsets: offsets)
        save()
    }
}
