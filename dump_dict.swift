
import Foundation

let fileManager = FileManager.default
if let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
    let url = appSupport.appendingPathComponent("WisprClone/learned_dictionary.json")
    if let data = try? Data(contentsOf: url), let str = String(data: data, encoding: .utf8) {
        print(str)
    } else {
        print("File not found or unreadable at \(url.path)")
    }
}
