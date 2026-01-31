
import Foundation

let fileManager = FileManager.default
if let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
    let url = appSupport.appendingPathComponent("WisprClone/wispr.log")
    if let data = try? Data(contentsOf: url), let str = String(data: data, encoding: .utf8) {
        print("--- Log File Content (Last 500 chars) ---")
        print(String(str.suffix(500)))
    } else {
        print("Log file not found or empty at \(url.path)")
    }
}
