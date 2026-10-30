//
//  WhisperBarActivity.swift
//  DynamicNotch
//
//  Zeigt in der Notch, solange WhisperBar diktiert. WhisperBar hat keine
//  Schnittstelle, und sein Menüleisten-Symbol liegt oft hinter der Notch.
//  macOS verrät aber ohne Berechtigung, welche App gerade das Mikrofon nutzt.
//  Aufgeklappt lässt sich die Aufnahme von hier beenden oder abbrechen.
//  WhisperBars eigenes Overlay schiebt die Mod dafür unter die Notch.
//

internal import AppKit
import Combine
import CoreAudio
import SwiftUI

extension NotchContentRegistry {
    enum WhisperBar {
        // Diktieren ist kurz und braucht sofort Rückmeldung, deshalb vor Claude (15)
        static let recording = NotchContentDescriptor(id: "whisperbar.recording", priority: 20)
    }
}

/// Fragt alle 0,4 s CoreAudio, ob WhisperBar gerade vom Mikrofon liest. Der Kurzbefehl
/// meldet Start und Ende schon vorher, weil Bluetooth-Kopfhörer erst nach etwa einer
/// Sekunde in den Headset-Modus wechseln.
@MainActor
final class WhisperBarMonitor: ObservableObject {
    static let bundleIdentifier = "com.kchromik.WhisperBar"

    /// Beim Wechsel in den Headset-Modus meldet macOS eine neue Lautstärke. Bis hierhin
    /// zeigt die Notch dafür keine Lautstärke-Anzeige, sonst käme die vor der Aufnahme.
    static var volumeHUDSuppressedUntil = Date.distantPast

    @Published private(set) var recordingStartedAt: Date?

    private var timer: Timer?
    /// Kurzbefehl gesehen, Mikrofon aber noch nicht an
    private var pendingSince: Date?
    /// Gerade beendet: Das Mikrofon läuft noch kurz nach, das ist keine neue Aufnahme
    private var stoppedAt: Date?

    func start() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
    }

    /// WhisperBars Kurzbefehl wurde gedrückt (von Hand oder über „Fertig“)
    func hotkeyPressed() {
        guard !NSRunningApplication.runningApplications(withBundleIdentifier: Self.bundleIdentifier).isEmpty else { return }
        MediaSourcesViewModel.log("WhisperBar: Kurzbefehl gesehen, \(recordingStartedAt == nil ? "Start" : "Ende")")
        if recordingStartedAt == nil {
            markStarted()
        } else {
            markStopped()
        }
    }

    func markStarted() {
        Self.volumeHUDSuppressedUntil = .now + 3
        recordingStartedAt = .now
        pendingSince = .now
        stoppedAt = nil
    }

    func markStopped() {
        Self.volumeHUDSuppressedUntil = .now + 3
        recordingStartedAt = nil
        pendingSince = nil
        stoppedAt = .now
    }

    private func poll() {
        let now = Date()
        let isRecording = Self.isUsingMicrophone(bundleIdentifier: Self.bundleIdentifier)
        if isRecording {
            if pendingSince != nil {
                MediaSourcesViewModel.log("WhisperBar: Mikrofon läuft")
            }
            pendingSince = nil
            let justStopped = stoppedAt.map { now.timeIntervalSince($0) < 2.5 } ?? false
            if recordingStartedAt == nil, !justStopped {
                // Ohne Kurzbefehl gestartet, z. B. über die Menüleiste
                Self.volumeHUDSuppressedUntil = now + 2
                recordingStartedAt = now
            }
        } else if recordingStartedAt != nil {
            // Nach dem Kurzbefehl bis zu 3 s aufs Mikrofon warten
            if let pendingSince, now.timeIntervalSince(pendingSince) < 3 { return }
            markStopped()
        }
    }

    private nonisolated static func isUsingMicrophone(bundleIdentifier: String) -> Bool {
        processObjects().contains { process in
            stringProperty(kAudioProcessPropertyBundleID, of: process) == bundleIdentifier
                && uintProperty(kAudioProcessPropertyIsRunningInput, of: process) == 1
        }
    }

    private nonisolated static func address(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
    }

    private nonisolated static func processObjects() -> [AudioObjectID] {
        var address = address(kAudioHardwarePropertyProcessObjectList)
        var size: UInt32 = 0
        let system = AudioObjectID(kAudioObjectSystemObject)
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr, size > 0 else { return [] }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &ids) == noErr else { return [] }
        return ids
    }

    private nonisolated static func stringProperty(_ selector: AudioObjectPropertySelector, of object: AudioObjectID) -> String? {
        var address = address(selector)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr else { return nil }
        return value?.takeRetainedValue() as String?
    }

    private nonisolated static func uintProperty(_ selector: AudioObjectPropertySelector, of object: AudioObjectID) -> UInt32 {
        var address = address(selector)
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr else { return 0 }
        return value
    }
}


/// Steuert WhisperBar von außen. Eine Schnittstelle gibt es nicht, also über
/// denselben Kurzbefehl, den man selbst drückt, und den Abbrechen-Knopf im Overlay.
/// Beides braucht die Bedienungshilfen, die DynamicNotch für die Medienquellen ohnehin hat.
enum WhisperBarRemote {
    struct Hotkey: Decodable {
        let keyCode: Int
        let modifiers: UInt
    }

    /// Aufnahme beenden: WhisperBar transkribiert und fügt den Text in die vorderste App ein.
    /// Hat der Klick auf die Notch DynamicNotch nach vorne geholt, kommt erst die App
    /// zurück, in der man geschrieben hat, sonst landet der Text nur in der Zwischenablage.
    @MainActor
    static func finish() {
        let hotkey = currentHotkey()
        let send = {
            post(keyCode: CGKeyCode(hotkey.keyCode), flags: CGEventFlags(rawValue: UInt64(hotkey.modifiers)))
        }
        let restored = WhisperBarTargetApp.restoreIfNeeded()
        MediaSourcesViewModel.log("WhisperBar: Fertig, vorige App nach vorne: \(restored ? WhisperBarTargetApp.last?.bundleIdentifier ?? "-" : "nicht nötig")")
        if restored {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: send)
        } else {
            send()
        }
    }

    /// Schiebt WhisperBars Overlay unter die Notch, wo DynamicNotch es verdeckt.
    /// Ausschalten geht nicht: Ohne Overlay fehlt der Abbrechen-Knopf, und Escape
    /// nimmt WhisperBar nicht an. WhisperBar setzt die Position bei jeder Aufnahme
    /// selbst zurück, das Verschieben bleibt also nicht hängen. Gibt die Fenster vorher/nachher zurück.
    @discardableResult
    nonisolated static func tuckOverlayUnderNotch(processIdentifier pid: pid_t, notchCenterX: CGFloat, notchHeight: CGFloat) -> [String] {
        let app = AXUIElementCreateApplication(pid)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &value) == .success,
              let windows = value as? [AXUIElement] else { return ["keine Fenster"] }
        var log: [String] = []
        for window in windows {
            guard var frame = frame(of: window) else { continue }
            log.append("vorher \(frame)")
            // Nur das kleine Overlay, nie ein Einstellungsfenster
            guard frame.height < 120, frame.width < 600 else { continue }
            // Unterkante bündig mit der kleinen Notch, der Rest ragt über den Bildschirmrand
            var target = CGPoint(x: notchCenterX - frame.width / 2, y: min(0, notchHeight - frame.height))
            if let position = AXValueCreate(.cgPoint, &target) {
                AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, position)
            }
            frame = self.frame(of: window) ?? frame
            log.append("nachher \(frame)")
        }
        return log
    }

    private nonisolated static func frame(of window: AXUIElement) -> CGRect? {
        var positionValue: CFTypeRef?
        var sizeValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &positionValue) == .success,
              AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &sizeValue) == .success,
              let positionValue, let sizeValue else { return nil }
        var point = CGPoint.zero
        var size = CGSize.zero
        AXValueGetValue(positionValue as! AXValue, .cgPoint, &point)
        AXValueGetValue(sizeValue as! AXValue, .cgSize, &size)
        return CGRect(origin: point, size: size)
    }

    /// Aufnahme verwerfen über den Abbrechen-Knopf im (unter der Notch versteckten) Overlay.
    /// Kein Escape als Ersatz: Das ginge auch an die vorderste App, und WhisperBar ignoriert es ohne Overlay.
    @MainActor
    static func cancel() {
        NotchWhisperBarEventsHandler.current?.monitor.markStopped()
        guard let pid = NSRunningApplication.runningApplications(withBundleIdentifier: WhisperBarMonitor.bundleIdentifier)
            .first?.processIdentifier else { return }
        Task.detached {
            MediaSourcesAccessibility.pressButton(processIdentifier: pid, labels: ["abbrechen", "cancel"])
        }
    }

    /// Versteckt das Overlay bei Aufnahmestart. Es erscheint mit kurzer Verzögerung, daher mehrere Versuche.
    static func tuckOverlayWhenShown(notchHeight: CGFloat) {
        guard let pid = NSRunningApplication.runningApplications(withBundleIdentifier: WhisperBarMonitor.bundleIdentifier)
            .first?.processIdentifier else { return }
        let centerX = NSScreen.screens.first?.frame.midX ?? 0
        // Das Overlay erscheint sofort, die Notch reagiert aber schon auf den Kurzbefehl
        for delay in [0.05, 0.3, 0.8, 1.5, 2.5] {
            DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + delay) {
                tuckOverlayUnderNotch(processIdentifier: pid, notchCenterX: centerX, notchHeight: notchHeight)
            }
        }
    }

    /// Kurzbefehl aus WhisperBars Einstellungen, sonst dessen Standard ⌥ Leertaste.
    /// Die Modifier sind dort als NSEvent-Flags gespeichert, deren Bits gleichen den CGEvent-Flags.
    static func currentHotkey() -> Hotkey {
        let value = CFPreferencesCopyAppValue("hotkeyCombo" as CFString, WhisperBarMonitor.bundleIdentifier as CFString)
        if let data = value as? Data, let hotkey = try? JSONDecoder().decode(Hotkey.self, from: data) {
            return hotkey
        }
        return Hotkey(keyCode: 49, modifiers: UInt(CGEventFlags.maskAlternate.rawValue))
    }

    private nonisolated static func post(keyCode: CGKeyCode, flags: CGEventFlags) {
        let source = CGEventSource(stateID: .hidSystemState)
        for isDown in [true, false] {
            let event = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: isDown)
            event?.flags = flags
            event?.post(tap: .cghidEventTap)
        }
    }
}

struct WhisperBarRecordingNotchContent: NotchContentProtocol, DynamicIslandCustomizable {
    let id = NotchContentRegistry.WhisperBar.recording.id
    let startedAt: Date
    let nowPlayingViewModel: NowPlayingViewModel
    let levelMeter: MicLevelMeter
    /// Beim Erstellen festgehalten; der Handler schickt die Anzeige neu, wenn sich das ändert
    let hasMusic: Bool

    var priority: Int { NotchContentRegistry.WhisperBar.recording.priority }
    var isExpandable: Bool { true }

    var strokeColor: Color {
        .red.opacity(0.35)
    }

    func size(baseWidth: CGFloat, baseHeight: CGFloat) -> CGSize {
        .init(width: baseWidth + 110, height: baseHeight)
    }

    func expandedSize(baseWidth: CGFloat, baseHeight: CGFloat) -> CGSize {
        .init(width: baseWidth + 200, height: baseHeight + (hasMusic ? 170 : 124))
    }

    func expandedDynamicIslandSize(baseWidth: CGFloat, baseHeight: CGFloat) -> CGSize {
        .init(width: baseWidth + 230, height: baseHeight + (hasMusic ? 160 : 114))
    }

    func expandedCornerRadius(baseRadius: CGFloat) -> (top: CGFloat, bottom: CGFloat) {
        (top: 26, bottom: 36)
    }

    func expandedDynamicIslandCornerRadius(baseHeight: CGFloat) -> CGFloat {
        baseHeight * 0.4
    }

    @MainActor
    func makeView() -> AnyView {
        AnyView(WhisperBarRecordingNotchView(startedAt: startedAt, levelMeter: levelMeter))
    }

    @MainActor
    func makeExpandedView() -> AnyView {
        AnyView(WhisperBarExpandedNotchView(startedAt: startedAt, nowPlayingViewModel: nowPlayingViewModel, levelMeter: levelMeter))
    }
}

struct WhisperBarRecordingNotchView: View {
    @Environment(\.notchScale) private var scale
    let startedAt: Date
    @ObservedObject var levelMeter: MicLevelMeter

    var body: some View {
        HStack {
            HStack(spacing: 5) {
                Image(systemName: "mic.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.red)
                    .symbolEffect(.pulse, options: .repeating)
                WhisperBarLevelBars(levelMeter: levelMeter)
            }

            Spacer()

            TimelineView(.periodic(from: startedAt, by: 1)) { context in
                Text(Self.elapsed(from: startedAt, to: context.date))
                    .font(.system(size: 13, weight: .semibold).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.9))
            }
        }
        .padding(.leading, 12.scaled(by: scale))
        .padding(.trailing, 14.scaled(by: scale))
    }

    static func elapsed(from start: Date, to now: Date) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(start)))
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

/// Aufgeklappt: Aufnahme beenden oder verwerfen, darunter bleibt die Musik bedienbar
struct WhisperBarExpandedNotchView: View {
    @Environment(\.isNotchlessScreen) private var isNotchlessScreen

    let startedAt: Date
    @ObservedObject var nowPlayingViewModel: NowPlayingViewModel
    @ObservedObject var levelMeter: MicLevelMeter

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "mic.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.red)
                    .symbolEffect(.pulse, options: .repeating)
                Text("Diktat läuft")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.9))
                Spacer()
                TimelineView(.periodic(from: startedAt, by: 1)) { context in
                    Text(WhisperBarRecordingNotchView.elapsed(from: startedAt, to: context.date))
                        .font(.system(size: 13, weight: .semibold).monospacedDigit())
                        .foregroundStyle(.white.opacity(0.6))
                }
            }

            WhisperBarLevelBars(levelMeter: levelMeter, count: 30, maxHeight: 20, barWidth: 3, spacing: 3)
                .frame(maxWidth: .infinity)

            HStack(spacing: 10) {
                actionButton("xmark", "Verwerfen", isPrimary: false) { WhisperBarRemote.cancel() }
                    .help("Aufnahme abbrechen, nichts einfügen")
                actionButton("checkmark", "Fertig", isPrimary: true) { WhisperBarRemote.finish() }
                    .help("Aufnahme beenden und Text einfügen")
            }

            if nowPlayingViewModel.snapshot != nil {
                Divider().overlay(.white.opacity(0.12))
                NotchMiniPlayerView(nowPlayingViewModel: nowPlayingViewModel)
            }
        }
        .padding(.horizontal, isNotchlessScreen ? 22 : 40)
        .padding(.top, isNotchlessScreen ? 12 : 20)
        .padding(.bottom, 12)
        .onNotchHorizontalSwipe(perform: NotchPageSwitcher.handleOverlaySwipe)
    }

    private func actionButton(_ systemImage: String, _ title: String, isPrimary: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.system(size: 12, weight: .bold))
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
            }
            .foregroundStyle(.white.opacity(isPrimary ? 1 : 0.85))
            .frame(maxWidth: .infinity)
            .frame(height: 30)
            .background(Capsule().fill(isPrimary ? Color.red.opacity(0.75) : .white.opacity(0.1)))
            .contentShape(Capsule())
        }
        .buttonStyle(PlaybackSourceButtonStyle())
    }
}

/// Pegelbalken: echter Mikrofonpegel, die neuesten Werte rechts. Ohne Mikrofon-Freigabe
/// wippen sie nur als Zeichen „hört zu“.
private struct WhisperBarLevelBars: View {
    @ObservedObject var levelMeter: MicLevelMeter
    var count = 4
    var maxHeight: CGFloat = 13
    var barWidth: CGFloat = 2.5
    var spacing: CGFloat = 2

    var body: some View {
        if levelMeter.isActive {
            let levels = levelMeter.history.suffix(count)
            HStack(spacing: spacing) {
                ForEach(Array(levels.enumerated()), id: \.offset) { _, level in
                    Capsule()
                        .fill(.white.opacity(0.85))
                        .frame(width: barWidth, height: 3 + (maxHeight - 3) * level)
                }
            }
            .frame(height: maxHeight + 1)
            .animation(.linear(duration: 0.08), value: levelMeter.history)
        } else {
            idleBars
        }
    }

    private var idleBars: some View {
        TimelineView(.animation(minimumInterval: 1 / 20)) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            HStack(spacing: spacing) {
                ForEach(0..<count, id: \.self) { index in
                    let phase = time * 7 + Double(index) * 1.3
                    Capsule()
                        .fill(.white.opacity(0.85))
                        .frame(width: barWidth, height: 4 + (maxHeight - 4) * abs(sin(phase) * cos(phase * 0.6)))
                }
            }
            .frame(height: maxHeight + 1)
        }
    }
}

/// Zeigt und versteckt die Diktier-Anzeige
@MainActor
final class NotchWhisperBarEventsHandler {
    /// Für die Prüfhilfe (NotchSnapshotDebugger)
    static weak var current: NotchWhisperBarEventsHandler?

    private let notchViewModel: NotchViewModel
    private let nowPlayingViewModel: NowPlayingViewModel
    let monitor = WhisperBarMonitor()
    private let hotkeyWatcher = WhisperBarHotkeyWatcher()
    private let levelMeter = MicLevelMeter()
    private var cancellables = Set<AnyCancellable>()

    init(notchViewModel: NotchViewModel, nowPlayingViewModel: NowPlayingViewModel) {
        self.notchViewModel = notchViewModel
        self.nowPlayingViewModel = nowPlayingViewModel
        Self.current = self
    }

    /// Prüfhilfe: Anzeige ohne echte Aufnahme
    func debugShow(_ isVisible: Bool) {
        if isVisible {
            show(startedAt: .now)
        } else {
            notchViewModel.send(.hideLiveActivity(id: NotchContentRegistry.WhisperBar.recording.id))
        }
    }

    func start() {
        monitor.$recordingStartedAt
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] startedAt in
                guard let self else { return }
                if let startedAt {
                    self.show(startedAt: startedAt)
                    self.levelMeter.start()
                    WhisperBarRemote.tuckOverlayWhenShown(notchHeight: self.notchViewModel.notchModel.baseHeight)
                } else {
                    self.levelMeter.stop()
                    self.notchViewModel.send(.hideLiveActivity(id: NotchContentRegistry.WhisperBar.recording.id))
                }
            }
            .store(in: &cancellables)

        // Startet oder endet die Musik während der Aufnahme, ändert sich die aufgeklappte Höhe
        nowPlayingViewModel.$snapshot
            .map { $0 != nil }
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] hasMusic in
                // Vor der Änderung gemeldet: den neuen Stand mitgeben statt snapshot zu lesen
                guard let self, let startedAt = self.monitor.recordingStartedAt else { return }
                self.show(startedAt: startedAt, hasMusic: hasMusic)
            }
            .store(in: &cancellables)

        hotkeyWatcher.onHotkey = { [weak self] in self?.monitor.hotkeyPressed() }
        hotkeyWatcher.start()
        WhisperBarTargetApp.startTracking()
        monitor.start()
    }

    func show(startedAt: Date, hasMusic: Bool? = nil) {
        notchViewModel.send(.showLiveActivity(WhisperBarRecordingNotchContent(
            startedAt: startedAt,
            nowPlayingViewModel: nowPlayingViewModel,
            levelMeter: levelMeter,
            hasMusic: hasMusic ?? (nowPlayingViewModel.snapshot != nil)
        )))
    }
}
