import ApplicationServices
import AppKit

/// Captures focus information about the currently focused text element
struct FocusInfo {
    let element: AXUIElement
    let pid: pid_t
    let bundleID: String?
    let initialValue: String?
}

/// Module to capture the focused text element before paste
class FocusCapture {
    
    /// Capture the currently focused element and its context
    /// Returns nil if focus cannot be captured (no permission, no focused element, etc.)
    /// Runs on a detached task to avoid blocking the main thread if AX calls hang
    static func captureCurrentFocus() async -> FocusInfo? {
        return await Task.detached(priority: .userInitiated) {
            // Get system-wide element
            let systemWide = AXUIElementCreateSystemWide()
            
            // Get focused application
            var focusedAppValue: CFTypeRef?
            let appResult = AXUIElementCopyAttributeValue(systemWide, kAXFocusedApplicationAttribute as CFString, &focusedAppValue)
            
            guard appResult == .success, let focusedApp = focusedAppValue else {
                Logger.warning("[FocusCapture] Failed to get focused application: \(appResult.rawValue)")
                return nil
            }
            
            let appElement = focusedApp as! AXUIElement
            
            // Get PID of focused app
            var pid: pid_t = 0
            AXUIElementGetPid(appElement, &pid)
            
            // Get bundle ID
            let bundleID = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier
            
            // Get focused UI element (text field/view)
            var focusedElementValue: CFTypeRef?
            let elementResult = AXUIElementCopyAttributeValue(appElement, kAXFocusedUIElementAttribute as CFString, &focusedElementValue)
            
            guard elementResult == .success, let focusedElement = focusedElementValue else {
                Logger.debug("Failed to get focused element: \(elementResult.rawValue)")
                return nil
            }
            
            let element = focusedElement as! AXUIElement
            
            // Try to read initial value (best-effort)
            let initialValue = readValue(from: element)
            
            return FocusInfo(
                element: element,
                pid: pid,
                bundleID: bundleID,
                initialValue: initialValue
            )
        }.value
    }
    
    /// Read the current value from an AX element
    /// Returns nil if value cannot be read (secure field, unsupported element, etc.)
    static func readValue(from element: AXUIElement) -> String? {
        var valueRef: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &valueRef)
        
        if result == .success, let value = valueRef {
            if let stringValue = value as? String {
                return stringValue
            }
            // Could be attributed string
            if let attrString = value as? NSAttributedString {
                return attrString.string
            }
        }
        
        // Try selected text as fallback (some elements only expose this)
        var selectedRef: CFTypeRef?
        let selectedResult = AXUIElementCopyAttributeValue(element, kAXSelectedTextAttribute as CFString, &selectedRef)
        if selectedResult == .success, let selected = selectedRef as? String {
            return selected
        }
        
        print("[FocusCapture] Could not read value from element: \(result.rawValue)")
        return nil
    }
    
    /// Walk up parent chain to find nearest editable ancestor with kAXValueAttribute
    /// This improves reliability for web/electron inputs
    static func findEditableAncestor(from element: AXUIElement) -> AXUIElement? {
        var current: AXUIElement? = element
        var depth = 0
        let maxDepth = 10
        
        while let el = current, depth < maxDepth {
            // Check if this element supports value attribute
            var valueRef: CFTypeRef?
            let result = AXUIElementCopyAttributeValue(el, kAXValueAttribute as CFString, &valueRef)
            
            if result == .success {
                // Also check if it's editable
                var editableRef: CFTypeRef?
                let editableResult = AXUIElementCopyAttributeValue(el, kAXRoleAttribute as CFString, &editableRef)
                if editableResult == .success, let role = editableRef as? String {
                    if role == kAXTextFieldRole as String || role == kAXTextAreaRole as String {
                        return el
                    }
                }
            }
            
            // Move to parent
            var parentRef: CFTypeRef?
            let parentResult = AXUIElementCopyAttributeValue(el, kAXParentAttribute as CFString, &parentRef)
            if parentResult == .success, let parent = parentRef {
                current = (parent as! AXUIElement)
            } else {
                break
            }
            
            depth += 1
        }
        
        return nil
    }
}
