import ApplicationServices
import AppKit

struct ContextManager {
    static func getSelectedText() -> String? {
        let systemWide = AXUIElementCreateSystemWide()
        
        var focusedElement: AnyObject?
        let error = AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &focusedElement)
        
        guard error == .success, let element = focusedElement as! AXUIElement? else {
            Logger.warning("ContextManager: Failed to get focused element (\(error.rawValue))")
            return nil
        }
        
        // Debug: Print the app we are trying to read from
        var pid: pid_t = 0
        AXUIElementGetPid(element, &pid)
        if let app = NSRunningApplication(processIdentifier: pid) {
            Logger.debug("ContextManager: Attempting capture from '\(app.localizedName ?? "Unknown App")' (PID: \(pid))")
        }
        
        // 1. Try Selected Text (Standard)
        var selectedText: AnyObject?
        let textError = AXUIElementCopyAttributeValue(element, kAXSelectedTextAttribute as CFString, &selectedText)
        
        if textError == .success, let text = selectedText as? String, !text.isEmpty {
            Logger.info("ContextManager: Success (Selected Text)")
            return text
        }
        
        Logger.info("ContextManager: SelectedText failed (\(textError.rawValue)). Trying fallbacks...")
        
        // 2. Try Value (e.g., text fields without explicit selection range implementation)
        var valueContent: AnyObject?
        let valueError = AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &valueContent)
        
        if valueError == .success, let text = valueContent as? String, !text.isEmpty {
            print("ContextManager: Success (Value Attribute)")
            // Note: This grabs ALL text in the field. For Command Mode, this might be okay if it's a small field (like a chat input),
            // but risky for a huge document. We'll accept it but log it.
            return text
        }
        
        print("ContextManager: Value failed (\(valueError.rawValue)).")
        return nil
    }
}
