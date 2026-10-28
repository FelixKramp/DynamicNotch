//
//  MediaSourcesViewModel.swift
//  DynamicNotch
//
//  Alle Apps, die gerade Medien melden (TIDAL, YouTube, Pocket Casts …),
//  jede einzeln steuerbar. Daten kommen vom Helfer in Resources/MediaSources.
//

internal import AppKit
import ApplicationServices
import Combine
import Foundation

struct MediaSource: Identifiable, Equatable, Decodable, Sendable {
    let bundleIdentifier: String
    /// Nur die aktive App nimmt Befehle über MediaRemote an, alle anderen
    /// bekommen einen Tastendruck (siehe sendKeyboardToggle).
    let isNowPlaying: Bool
    let parentBundleIdentifier: String?
    let displayName: String?
    let processIdentifier: Int32
    let playbackState: Int
    let title: String?
    let artist: String?
    let album: String?

    var id: String { bundleIdentifier }
    var isPlaying: Bool { playbackState == 1 }

    var name: String {
        if let displayName, !displayName.isEmpty { return displayName }
        return NSRunningApplication(processIdentifier: processIdentifier)?.localizedName ?? bundleIdentifier
    }

    var subtitle: String {
        [title, artist]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }
}

enum MediaSourceCommand: Int, Sendable {
    case play = 0
    case pause = 1
    case togglePlayPause = 2
    case nextTrack = 4
    case previousTrack = 5

    var isPlayPause: Bool {
        self == .play || self == .pause || self == .togglePlayPause
    }
}

@MainActor
final class MediaSourcesViewModel: ObservableObject {
    static let shared = MediaSourcesViewModel()

    @Published private(set) var sources: [MediaSource] = []

    private var pollTask: Task<Void, Never>?
    private var activeObservers = 0
    private var iconCache: [String: NSImage] = [:]

    func startObserving() {
        activeObservers += 1
        guard pollTask == nil else { return }

        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                try? await Task.sleep(for: .seconds(1.5))
            }
        }
    }

    func stopObserving() {
        activeObservers = max(0, activeObservers - 1)
        guard activeObservers == 0 else { return }
        pollTask?.cancel()
        pollTask = nil
    }

    func refresh() async {
        let result = await Self.runHelper(["list"])
        guard result.status == 0,
              let decoded = try? JSONDecoder().decode([MediaSource].self, from: result.data) else { return }

        // Apps ohne Titel (z. B. Xcode) melden sich teils leer an und gehören nicht in die Liste.
        // Spielende zuerst, sonst Reihenfolge von macOS (zuletzt aktiv zuerst)
        let sorted = decoded
            .filter { !($0.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .enumerated()
            .sorted { lhs, rhs in
                if lhs.element.isPlaying != rhs.element.isPlaying { return lhs.element.isPlaying }
                return lhs.offset < rhs.offset
            }
            .map(\.element)

        if sorted != sources {
            sources = sorted
        }

        // Neue Quellen vorbereiten, solange niemand tippt
        let newProcesses = sorted.map(\.processIdentifier).filter { !preparedProcesses.contains($0) }
        guard !newProcesses.isEmpty, AXIsProcessTrusted() else { return }
        preparedProcesses.formUnion(newProcesses)
        Task.detached(priority: .utility) {
            newProcesses.forEach { MediaSourcesAccessibility.prepare(processIdentifier: $0) }
        }
    }

    private var preparedProcesses = Set<Int32>()

    func send(_ command: MediaSourceCommand, to source: MediaSource) {
        Task {
            let result = await Self.runHelper(["send", source.bundleIdentifier, String(command.rawValue)])
            // Der Tastendruck kann nur Play/Pause, kein Weiter
            // Die Taste schaltet nur um: Pause an eine pausierte App würde sie starten
            let alreadyThere = (command == .pause && !source.isPlaying) || (command == .play && source.isPlaying)
            if result.status == Self.notNowPlayingStatus, command.isPlayPause, !alreadyThere {
                await sendKeyboardToggle(to: source)
            }
            try? await Task.sleep(for: .milliseconds(400))
            await refresh()
        }
    }

    /// Holt die App kurz nach vorne, drückt ihre Play/Pause-Taste und gibt den
    /// Fokus zurück. Braucht die Berechtigung „Bedienungshilfen“.
    private func sendKeyboardToggle(to source: MediaSource) async {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        guard AXIsProcessTrustedWithOptions(options) else {
            Self.log("keine Bedienungshilfen-Berechtigung")
            return
        }
        guard let app = NSRunningApplication(processIdentifier: source.processIdentifier) else { return }

        // Erst ohne Fensterwechsel versuchen: den Knopf der App direkt drücken
        let pid = source.processIdentifier
        let pressed = await Task.detached(priority: .userInitiated) {
            MediaSourcesAccessibility.pressPlayPause(processIdentifier: pid)
        }.value
        if let pressed {
            Self.log("Knopf \"\(pressed)\" in \(source.bundleIdentifier) gedrückt (ohne Flackern)")
            return
        }
        Self.log("kein Play/Pause-Knopf in \(source.bundleIdentifier) gefunden, nutze Tastendruck")

        let previous = NSWorkspace.shared.frontmostApplication
        // NSRunningApplication.activate() greift seit macOS 14 nicht, wenn die
        // aufrufende App selbst im Hintergrund ist. openApplication darf das.
        await bringToFront(app)
        Self.log("vorne nach Aktivieren: \(NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "-")")

        // YouTube reagiert auf "k" auch ohne Fokus im Player, die anderen auf die Leertaste
        let keyCode: CGKeyCode = source.bundleIdentifier.hasPrefix("com.google.Chrome.app") ? 40 : 49
        let isFront = NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier
        for isDown in [true, false] {
            let event = CGEvent(keyboardEventSource: CGEventSource(stateID: .hidSystemState), virtualKey: keyCode, keyDown: isDown)
            if isFront {
                event?.post(tap: .cghidEventTap)
            } else {
                event?.postToPid(source.processIdentifier)
            }
        }
        Self.log("Taste \(keyCode) an \(source.bundleIdentifier) gesendet (vorne: \(isFront))")

        try? await Task.sleep(for: .milliseconds(200))
        if let previous, previous.processIdentifier != app.processIdentifier {
            await bringToFront(previous)
        }
    }

    private func bringToFront(_ app: NSRunningApplication) async {
        guard let url = app.bundleURL else {
            app.activate()
            return
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        _ = try? await NSWorkspace.shared.openApplication(at: url, configuration: configuration)
        for _ in 0..<10 {
            if NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier { return }
            try? await Task.sleep(for: .milliseconds(50))
        }
    }

    /// Protokoll für die Fehlersuche: ~/Library/Application Support/DynamicNotch/media-sources.log
    static func log(_ message: String) {
        let url = ClaudeActivityViewModel.stateDirectory
            .deletingLastPathComponent()
            .appendingPathComponent("media-sources.log")
        let line = "\(Date().formatted(date: .omitted, time: .standard)) \(message)\n"
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(Data(line.utf8))
            try? handle.close()
        } else {
            try? line.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    private static let notNowPlayingStatus: Int32 = 3

    func icon(for source: MediaSource) -> NSImage? {
        if let cached = iconCache[source.bundleIdentifier] { return cached }

        let icon = NSRunningApplication(processIdentifier: source.processIdentifier)?.icon
            ?? NSWorkspace.shared.urlForApplication(withBundleIdentifier: source.bundleIdentifier)
                .map { NSWorkspace.shared.icon(forFile: $0.path) }
        iconCache[source.bundleIdentifier] = icon
        return icon
    }

    func activate(_ source: MediaSource) {
        NSRunningApplication(processIdentifier: source.processIdentifier)?.activate()
    }

    private nonisolated static func runHelper(_ arguments: [String]) async -> (status: Int32, data: Data) {
        guard let script = Bundle.main.url(forResource: "notch-media-sources", withExtension: "pl"),
              let library = Bundle.main.url(forResource: "NotchMediaSources", withExtension: "dylib") else {
            return (-1, Data())
        }

        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
                process.arguments = [script.path, library.path] + arguments
                let output = Pipe()
                process.standardOutput = output
                process.standardError = Pipe()

                do {
                    try process.run()
                    let data = output.fileHandleForReading.readDataToEndOfFile()
                    process.waitUntilExit()
                    continuation.resume(returning: (process.terminationStatus, data))
                } catch {
                    continuation.resume(returning: (-1, Data()))
                }
            }
        }
    }
}
