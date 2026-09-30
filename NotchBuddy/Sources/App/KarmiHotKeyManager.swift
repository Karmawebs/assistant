import AppKit
import Carbon

extension Notification.Name {
    static let karmiHotKeyPressed = Notification.Name("karmiHotKeyPressed")
    static let karmiHotKeyReleased = Notification.Name("karmiHotKeyReleased")
}

final class KarmiHotKeyManager: @unchecked Sendable {
    static let shared = KarmiHotKeyManager()

    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private var started = false

    private init() {}

    func start() {
        guard !started else { return }
        started = true

        var eventTypes = [
            EventTypeSpec(
                eventClass: OSType(kEventClassKeyboard),
                eventKind: UInt32(kEventHotKeyPressed)
            ),
            EventTypeSpec(
                eventClass: OSType(kEventClassKeyboard),
                eventKind: UInt32(kEventHotKeyReleased)
            )
        ]

        let userData = UnsafeMutableRawPointer(
            Unmanaged.passUnretained(self).toOpaque()
        )

        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData in
                guard let event, let userData else { return noErr }

                let manager = Unmanaged<KarmiHotKeyManager>
                    .fromOpaque(userData)
                    .takeUnretainedValue()

                var hotKeyID = EventHotKeyID()
                let status = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )

                guard status == noErr, hotKeyID.id == 1 else { return noErr }

                let kind = GetEventKind(event)

                if kind == UInt32(kEventHotKeyPressed) {
                    DispatchQueue.main.async {
                        NotificationCenter.default.post(
                            name: .karmiHotKeyPressed,
                            object: manager
                        )
                    }
                } else if kind == UInt32(kEventHotKeyReleased) {
                    DispatchQueue.main.async {
                        NotificationCenter.default.post(
                            name: .karmiHotKeyReleased,
                            object: manager
                        )
                    }
                }

                return noErr
            },
            eventTypes.count,
            &eventTypes,
            userData,
            &handlerRef
        )

        let hotKeyID = EventHotKeyID(
            signature: OSType(0x4B41524D), // 'KARM'
            id: 1
        )

        RegisterEventHotKey(
            UInt32(kVK_ANSI_K),
            UInt32(optionKey),
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
    }

    func stop() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
        }
        if let handlerRef {
            RemoveEventHandler(handlerRef)
        }
        hotKeyRef = nil
        handlerRef = nil
        started = false
    }
}
