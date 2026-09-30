import AppKit
import ApplicationServices

extension Notification.Name {
    static let karmiGlobalHotkeyDown = Notification.Name("karmiGlobalHotkeyDown")
    static let karmiGlobalHotkeyUp = Notification.Name("karmiGlobalHotkeyUp")
}

final class GlobalKarmiHotkeyInterceptor {
    static let shared = GlobalKarmiHotkeyInterceptor()

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var kIsDown = false

    private init() {}

    func start() {
        stop()

        let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [promptKey: true] as CFDictionary

        guard AXIsProcessTrustedWithOptions(options) else {
            return
        }

        let mask =
            (CGEventMask(1) << CGEventType.keyDown.rawValue) |
            (CGEventMask(1) << CGEventType.keyUp.rawValue)

        let refcon = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, userInfo in
                guard let userInfo else {
                    return Unmanaged.passUnretained(event)
                }

                let interceptor = Unmanaged<GlobalKarmiHotkeyInterceptor>
                    .fromOpaque(userInfo)
                    .takeUnretainedValue()

                if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                    if let eventTap = interceptor.eventTap {
                        CGEvent.tapEnable(tap: eventTap, enable: true)
                    }
                    return Unmanaged.passUnretained(event)
                }

                let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
                guard keyCode == 40 else { // K
                    return Unmanaged.passUnretained(event)
                }

                if type == .keyDown {
                    let flags = event.flags
                    let hasCommand = flags.contains(.maskCommand)
                    let hasOtherModifier =
                        flags.contains(.maskAlternate) ||
                        flags.contains(.maskControl) ||
                        flags.contains(.maskShift)

                    guard hasCommand && !hasOtherModifier else {
                        return Unmanaged.passUnretained(event)
                    }

                    // Consume repeat events too, but notify only once.
                    if !interceptor.kIsDown {
                        interceptor.kIsDown = true
                        DispatchQueue.main.async {
                            NotificationCenter.default.post(name: .karmiGlobalHotkeyDown, object: nil)
                        }
                    }
                    return nil
                }

                if type == .keyUp, interceptor.kIsDown {
                    interceptor.kIsDown = false
                    DispatchQueue.main.async {
                        NotificationCenter.default.post(name: .karmiGlobalHotkeyUp, object: nil)
                    }
                    return nil
                }

                return Unmanaged.passUnretained(event)
            },
            userInfo: refcon
        ) else {
            return
        }

        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)

        if let runLoopSource {
            CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
        }
    }

    func stop() {
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        if let eventTap {
            CFMachPortInvalidate(eventTap)
        }
        runLoopSource = nil
        eventTap = nil
        kIsDown = false
    }
}
