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
        // macOS disables a tap (without tearing it down) if the callback is
        // ever too slow, and can do the same around sleep/lock. Left
        // unhandled, this looks identical to the tap never having existed --
        // keystrokes just silently stop being seen, permanently, until relaunch.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            manager.reEnable()
            return Unmanaged.passUnretained(event)
        }
        manager.handle(type: type, event: event)
        return Unmanaged.passUnretained(event)
    }

    fileprivate func reEnable() {
        guard let tap = eventTap else { return }
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    /// Full rebuild rather than just re-enabling -- covers wake-from-sleep
    /// cases where the mach port itself, not just the enabled flag, is the
    /// part that didn't survive.
    @discardableResult
    func restart() -> Bool {
        stop()
        return start()
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

    /// Reported in diagnostics only. Accessibility is *not* an alternative
    /// route to reading keystrokes, however much it looks like one: listening
    /// to keyDown/keyUp requires Input Monitoring specifically, and a process
    /// trusted only for Accessibility still gets `nil` back from `tapCreate`.
    ///
    /// This is recorded precisely because it is misleading. Measured on macOS
    /// 26.6: `AXIsProcessTrusted() == true`, `CGPreflightListenEventAccess()
    /// == false`, tap dead. An earlier version treated the two as
    /// interchangeable and the Accessibility grant silently convinced the app
    /// it was working. Never gate on this -- gate on `isLive`.
    static func hasAccessibilityPermission() -> Bool {
        AXIsProcessTrusted()
    }

    /// True only if the tap actually exists and is currently turned on --
    /// not just "start() was called at some point". Used by the one-button
    /// test-and-fix action rather than injecting a fake keystroke, which
    /// would risk typing into whatever app the user is actually focused on.
    var isLive: Bool {
        guard let tap = eventTap else { return false }
        return CGEvent.tapIsEnabled(tap: tap)
    }
}
