import Cocoa
import CoreGraphics

// Minimal standalone diagnostic: proves the CGEventTap + Input Monitoring
// permission mechanism works in complete isolation, with zero audio, zero
// menu bar, zero app bundle. Run this directly in your own Terminal window
// so there's no ambiguity about which process needs permission, and the
// proof is something you SEE (printed lines), not something you have to hear.

final class Diagnostic {
    private var tickCount = 0
    private var retryTimer: Timer?
    private var eventTap: CFMachPort?

    // CGEventTapCallBack must be a plain C function pointer (no captured
    // context), so state is passed through the `userInfo`/refcon pointer
    // instead of being captured directly.
    private let callback: CGEventTapCallBack = { _, type, event, refcon in
        guard type == .keyDown, let refcon = refcon else {
            return Unmanaged.passUnretained(event)
        }
        let diag = Unmanaged<Diagnostic>.fromOpaque(refcon).takeUnretainedValue()
        diag.tickCount += 1
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        print("TICK #\(diag.tickCount) keyDown keyCode=\(keyCode)")
        return Unmanaged.passUnretained(event)
    }

    func run() {
        setbuf(stdout, nil) // unbuffered so lines show up the instant they're printed
        print("=== Klack Diagnostic ===")
        attempt()
        retryTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.attempt()
        }
        if let t = retryTimer {
            RunLoop.current.add(t, forMode: .common)
        }
        CFRunLoopRun()
    }

    private func attempt() {
        if eventTap != nil { return } // already succeeded, nothing to do

        let granted = CGPreflightListenEventAccess()
        print("[status] Input Monitoring granted = \(granted)")

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
            print("[status] CGEvent.tapCreate FAILED (returned nil).")
            if !granted {
                print("[action] Requesting permission now — check System Settings > Privacy & Security > Input Monitoring for 'KlackDiag' and turn it on.")
                CGRequestListenEventAccess()
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") {
                    NSWorkspace.shared.open(url)
                }
            }
            print("[status] Will keep retrying every 2 seconds...")
            return
        }

        eventTap = tap
        print("[status] Event tap created successfully!")
        print("[status] Type anywhere now — you should see TICK lines appear below:")
        let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        retryTimer?.invalidate()
        retryTimer = nil
    }
}

let diagnostic = Diagnostic()
diagnostic.run()
