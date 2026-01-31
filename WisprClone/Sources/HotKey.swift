import Carbon
import Foundation

enum InputMode {
    case dictation
    case command
}

protocol HotKeyDelegate: AnyObject {
    func hotKeyDown(mode: InputMode)
    func hotKeyUp(mode: InputMode)
}

class HotKey {
    weak var delegate: HotKeyDelegate?
    private var hotKeyRefs: [UInt32: EventHotKeyRef] = [:]
    private var eventHandlerRefs: [EventHandlerRef] = []
    
    init() {
        // Register Control+Space (Dictation) -> ID 1
        register(id: 1, keyCode: UInt32(kVK_Space), modifiers: UInt32(controlKey))
        
        // Register Option+Control+Space (Command) -> ID 2
        register(id: 2, keyCode: UInt32(kVK_Space), modifiers: UInt32(optionKey | controlKey))
        
        installEventHandler()
    }
    
    deinit {
        for ref in hotKeyRefs.values {
            UnregisterEventHotKey(ref)
        }
        for handler in eventHandlerRefs {
            RemoveEventHandler(handler)
        }
    }
    
    private func register(id: UInt32, keyCode: UInt32, modifiers: UInt32) {
        let hotKeyID = EventHotKeyID(signature: OSType(bitPattern: 0x57495350), id: id)
        var eventHotKeyRef: EventHotKeyRef?
        
        let status = RegisterEventHotKey(keyCode,
                                         modifiers,
                                         hotKeyID,
                                         GetApplicationEventTarget(),
                                         0,
                                         &eventHotKeyRef)
        
        if status == noErr, let ref = eventHotKeyRef {
            hotKeyRefs[id] = ref
            Logger.info("[HotKey] Successfully registered ID \(id)")
        } else {
            Logger.error("[HotKey] Failed to register hotkey ID \(id): \(status)")
        }
    }
    
    private func installEventHandler() {
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        var eventTypeRelease = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased))

        let handler: EventHandlerUPP = { (_, event, userData) -> OSStatus in
            guard let userData = userData else { return noErr }
            // Get HotKey ID
            var hotKeyID = EventHotKeyID()
            let err = GetEventParameter(event,
                                        EventParamName(kEventParamDirectObject),
                                        EventParamType(typeEventHotKeyID),
                                        nil,
                                        MemoryLayout<EventHotKeyID>.size,
                                        nil,
                                        &hotKeyID)
            
            let kind = GetEventKind(event)
            let mySelf = Unmanaged<HotKey>.fromOpaque(userData).takeUnretainedValue()

            if err == noErr {
                let mode: InputMode = (hotKeyID.id == 2) ? .command : .dictation
                
                if kind == kEventHotKeyPressed {
                    mySelf.delegate?.hotKeyDown(mode: mode)
                } else if kind == kEventHotKeyReleased {
                    mySelf.delegate?.hotKeyUp(mode: mode)
                }
            } else if kind == kEventHotKeyReleased {
                // FAIL-SAFE
                print("HotKey Release Fallback Triggered")
                mySelf.delegate?.hotKeyUp(mode: .dictation)
            }
            return noErr
        }
        
        var handlerRef: EventHandlerRef?
        if InstallEventHandler(GetApplicationEventTarget(), handler, 1, &eventType, Unmanaged.passUnretained(self).toOpaque(), &handlerRef) == noErr, let ref = handlerRef {
            eventHandlerRefs.append(ref)
        }
        
        var handlerRefRelease: EventHandlerRef?
        if InstallEventHandler(GetApplicationEventTarget(), handler, 1, &eventTypeRelease, Unmanaged.passUnretained(self).toOpaque(), &handlerRefRelease) == noErr, let ref = handlerRefRelease {
            eventHandlerRefs.append(ref)
        }
    }
}
