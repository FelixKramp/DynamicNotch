//
//  WhisperBarActivity.swift
//  DynamicNotch
//
//  Zeigt in der Notch, solange WhisperBar diktiert. WhisperBar hat keine
//  Schnittstelle, und sein Menüleisten-Symbol liegt oft hinter der Notch.
//  macOS verrät aber ohne Berechtigung, welche App gerade das Mikrofon nutzt.
//

import Combine
import CoreAudio
import SwiftUI

extension NotchContentRegistry {
    enum WhisperBar {
        // Diktieren ist kurz und braucht sofort Rückmeldung, deshalb vor Claude (15)
        static let recording = NotchContentDescriptor(id: "whisperbar.recording", priority: 20)
    }
}

/// Fragt alle 0,4 s CoreAudio, ob WhisperBar gerade vom Mikrofon liest
@MainActor
final class WhisperBarMonitor: ObservableObject {
    static let bundleIdentifier = "com.kchromik.WhisperBar"

    @Published private(set) var recordingStartedAt: Date?

    private var timer: Timer?

    func start() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
    }

    private func poll() {
        let isRecording = Self.isUsingMicrophone(bundleIdentifier: Self.bundleIdentifier)
        if isRecording, recordingStartedAt == nil {
            recordingStartedAt = .now
        } else if !isRecording, recordingStartedAt != nil {
            recordingStartedAt = nil
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

struct WhisperBarRecordingNotchContent: NotchContentProtocol, DynamicIslandCustomizable {
    let id = NotchContentRegistry.WhisperBar.recording.id
    let startedAt: Date

    var priority: Int { NotchContentRegistry.WhisperBar.recording.priority }

    var strokeColor: Color {
        .red.opacity(0.35)
    }

    func size(baseWidth: CGFloat, baseHeight: CGFloat) -> CGSize {
        .init(width: baseWidth + 110, height: baseHeight)
    }

    @MainActor
    func makeView() -> AnyView {
        AnyView(WhisperBarRecordingNotchView(startedAt: startedAt))
    }
}

struct WhisperBarRecordingNotchView: View {
    @Environment(\.notchScale) private var scale
    let startedAt: Date

    var body: some View {
        HStack {
            HStack(spacing: 5) {
                Image(systemName: "mic.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.red)
                    .symbolEffect(.pulse, options: .repeating)
                WhisperBarLevelBars()
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

    private static func elapsed(from start: Date, to now: Date) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(start)))
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

/// Wippende Balken als Zeichen „hört zu“. Den echten Pegel sieht nur WhisperBar.
private struct WhisperBarLevelBars: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 20)) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            HStack(spacing: 2) {
                ForEach(0..<4, id: \.self) { index in
                    let phase = time * 7 + Double(index) * 1.3
                    Capsule()
                        .fill(.white.opacity(0.85))
                        .frame(width: 2.5, height: 4 + 9 * abs(sin(phase) * cos(phase * 0.6)))
                }
            }
            .frame(height: 14)
        }
    }
}

/// Zeigt und versteckt die Diktier-Anzeige
@MainActor
final class NotchWhisperBarEventsHandler {
    private let notchViewModel: NotchViewModel
    private let monitor = WhisperBarMonitor()
    private var cancellable: AnyCancellable?

    init(notchViewModel: NotchViewModel) {
        self.notchViewModel = notchViewModel
    }

    func start() {
        cancellable = monitor.$recordingStartedAt
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] startedAt in
                guard let self else { return }
                if let startedAt {
                    self.notchViewModel.send(.showLiveActivity(WhisperBarRecordingNotchContent(startedAt: startedAt)))
                } else {
                    self.notchViewModel.send(.hideLiveActivity(id: NotchContentRegistry.WhisperBar.recording.id))
                }
            }
        monitor.start()
    }
}
