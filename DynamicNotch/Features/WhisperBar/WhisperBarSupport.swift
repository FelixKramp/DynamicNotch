//
//  WhisperBarSupport.swift
//  DynamicNotch
//
//  Hilfen für die Diktat-Anzeige: den Kurzbefehl mitlesen (damit die Notch sofort
//  reagiert und nicht erst, wenn das Bluetooth-Mikrofon nach einer Sekunde läuft),
//  sich die App merken, in die eingefügt werden soll, und den echten Mikrofonpegel messen.
//

internal import AppKit
import AVFoundation
import Combine
import SwiftUI

/// Liest WhisperBars Kurzbefehl mit, ohne ihn abzufangen. Braucht die Bedienungshilfen.
@MainActor
final class WhisperBarHotkeyWatcher {
    var onHotkey: (() -> Void)?

    private var tap: CFMachPort?
    private var hotkey = WhisperBarRemote.currentHotkey()
    private var hotkeyReadAt = Date()

    func start() {
        guard tap == nil else { return }
        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
        let callback: CGEventTapCallBack = { _, type, event, refcon in
            if let refcon {
                let watcher = Unmanaged<WhisperBarHotkeyWatcher>.fromOpaque(refcon).takeUnretainedValue()
                MainActor.assumeIsolated { watcher.handle(type: type, event: event) }
            }
            return Unmanaged.passUnretained(event)
        }
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { return }
        self.tap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    private func handle(type: CGEventType, event: CGEvent) {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return
        }
        guard type == .keyDown, event.getIntegerValueField(.keyboardEventAutorepeat) == 0 else { return }

        // Den Kurzbefehl ab und zu neu lesen, falls er in WhisperBar geändert wurde
        if Date().timeIntervalSince(hotkeyReadAt) > 10 {
            hotkey = WhisperBarRemote.currentHotkey()
            hotkeyReadAt = Date()
        }
        let relevant: CGEventFlags = [.maskCommand, .maskShift, .maskAlternate, .maskControl]
        let wanted = CGEventFlags(rawValue: UInt64(hotkey.modifiers)).intersection(relevant)
        guard event.getIntegerValueField(.keyboardEventKeycode) == Int64(hotkey.keyCode),
              event.flags.intersection(relevant) == wanted else { return }
        onHotkey?()
    }
}

/// Merkt sich die zuletzt aktive fremde App. Klickt man auf die Notch, wird
/// DynamicNotch aktiv, und WhisperBar fände beim Einfügen kein Textfeld mehr.
@MainActor
enum WhisperBarTargetApp {
    private(set) static var last: NSRunningApplication?
    private static var observer: NSObjectProtocol?

    static func startTracking() {
        guard observer == nil else { return }
        remember(NSWorkspace.shared.frontmostApplication)
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { notification in
            let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            MainActor.assumeIsolated { remember(app) }
        }
    }

    /// Holt die App zurück nach vorne, falls DynamicNotch selbst gerade vorne ist.
    /// Gibt zurück, ob dafür gewartet werden muss.
    static func restoreIfNeeded() -> Bool {
        guard NSWorkspace.shared.frontmostApplication?.bundleIdentifier == Bundle.main.bundleIdentifier,
              let last, !last.isTerminated else { return false }
        last.activate()
        return true
    }

    private static func remember(_ app: NSRunningApplication?) {
        guard let app,
              app.bundleIdentifier != Bundle.main.bundleIdentifier,
              app.bundleIdentifier != WhisperBarMonitor.bundleIdentifier else { return }
        last = app
    }
}

/// Echter Mikrofonpegel für die Balken. Braucht einmal die Mikrofon-Freigabe;
/// ohne sie bleiben die Balken bei der Animation.
@MainActor
final class MicLevelMeter: ObservableObject {
    static let historyLength = 30

    @Published private(set) var history = [CGFloat](repeating: 0, count: historyLength)
    @Published private(set) var isActive = false

    private var engine: AVAudioEngine?
    private var wantsToRun = false

    func start() {
        wantsToRun = true
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            run()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
                guard granted else { return }
                Task { @MainActor in
                    guard let self, self.wantsToRun else { return }
                    self.run()
                }
            }
        default:
            break
        }
    }

    func stop() {
        wantsToRun = false
        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()
        engine = nil
        isActive = false
        history = [CGFloat](repeating: 0, count: Self.historyLength)
    }

    private func run() {
        guard engine == nil else { return }
        let engine = AVAudioEngine()
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { return }

        input.installTap(onBus: 0, bufferSize: 2048, format: format, block: Self.makeTap { [weak self] level in
            Task { @MainActor in self?.push(level) }
        })
        do {
            try engine.start()
            self.engine = engine
            isActive = true
        } catch {
            input.removeTap(onBus: 0)
        }
    }

    private func push(_ level: CGFloat) {
        guard isActive else { return }
        history.removeFirst()
        history.append(level)
    }

    /// Läuft im Audio-Thread, deshalb außerhalb des MainActor gebaut
    private nonisolated static func makeTap(onLevel: @escaping @Sendable (CGFloat) -> Void) -> AVAudioNodeTapBlock {
        { buffer, _ in
            guard let samples = buffer.floatChannelData?[0], buffer.frameLength > 0 else { return }
            let count = Int(buffer.frameLength)
            var sum: Float = 0
            for index in 0..<count {
                sum += samples[index] * samples[index]
            }
            let decibels = 20 * log10(max(sqrt(sum / Float(count)), 0.000_000_1))
            // -50 dB ist Stille, -10 dB lautes Sprechen
            onLevel(CGFloat(min(max((decibels + 50) / 40, 0), 1)))
        }
    }
}
