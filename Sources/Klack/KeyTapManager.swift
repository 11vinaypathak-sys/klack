import Cocoa
import CoreGraphics

/// Wraps a CGEventTap that listens (read-only) to global keyDown/keyUp events.
/// macOS requires the app to be granted "Input Monitoring" permission before
/// this tap will actually receive events — tapCreate succeeds either way, but
/// the callback silently receives nothing until the user grants it.
final class KeyTapManager {
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var attachedRunLoop: CFRunLoop?

    var isEnabled: Bool = true
    var onKeyDown: ((Bool) -> Void)?
    var onKeyUp: ((Bool) -> Void)?

    private static let spaceKeyCode: Int64 = 49

    private let callback: CGEventTapCallBack = { _, type, event, refcon in
        guard let refcon = refcon else { return Unmanaged.passUnretained(event) }
        let manager = Unmanaged<KeyTapManager>.fromOpaque(refcon).takeUnretainedValue()
        manager.handle(type: type, event: event)
        return Unmanaged.passUnretained(event)
    }

    @discardableResult
    func start() -> Bool {
        if eventTap != nil {
            return true
        }
        let mask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue)
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: CGEventMask(mask),
            callback: callback,
            userInfo: selfPtr
        ) else {
            return false
        }

        eventTap = tap
        attachedRunLoop = CFRunLoopGetCurrent()
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        if let source = runLoopSource {
            CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        }
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    deinit {
        // The tap holds a non-owning pointer back to self, so it must not
        // outlive this object — otherwise its callback resurrects freed memory.
        stop()
    }

    func stop() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        if let source = runLoopSource {
            // Remove from the run loop the tap was actually attached to, not
            // whichever one happens to be calling stop().
            CFRunLoopRemoveSource(attachedRunLoop ?? CFRunLoopGetCurrent(), source, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
        attachedRunLoop = nil
    }

    private func handle(type: CGEventType, event: CGEvent) {
        guard isEnabled else { return }
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let isSpace = keyCode == Self.spaceKeyCode
        switch type {
        case .keyDown:
            onKeyDown?(isSpace)
        case .keyUp:
            onKeyUp?(isSpace)
        default:
            break
        }
    }

    static func hasInputMonitoringPermission() -> Bool {
        if #available(macOS 10.15, *) {
            return CGPreflightListenEventAccess()
        }
        return true
    }

    static func requestInputMonitoringPermission() {
        if #available(macOS 10.15, *) {
            CGRequestListenEventAccess()
        }
    }
}
