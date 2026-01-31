import Foundation

struct LearnedEntry: Codable, Identifiable {
    var id: String { canonical }
    let canonical: String // The correct form (e.g., "Aadhar")
    var aliases: Set<String> // Incorrect forms (e.g., ["order", "Order"])
    var count: Int // How many times this correction was seen
    var lastUpdated: Date
    var bundleID: String? // Optional app scope (nil = global)
}

let fileManager = FileManager.default
let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
let directory = appSupport.appendingPathComponent("WisprClone", isDirectory: true)
let entriesUrl = directory.appendingPathComponent("learned_dictionary.json")

print("Checking file at: \(entriesUrl.path)")

if fileManager.fileExists(atPath: entriesUrl.path) {
    do {
        let data = try Data(contentsOf: entriesUrl)
        print("Data size: \(data.count) bytes")
        let string = String(data: data, encoding: .utf8)!
        print("Content: \(string)")
        
        let decoder = JSONDecoder()
        let entries = try decoder.decode([LearnedEntry].self, from: data)
        print("Successfully decoded \(entries.count) entries.")
        for entry in entries {
            print("- \(entry.canonical): \(entry.aliases)")
        }
    } catch {
        print("❌ Decoding failed: \(error)")
    }
} else {
    print("❌ File not found")
}
