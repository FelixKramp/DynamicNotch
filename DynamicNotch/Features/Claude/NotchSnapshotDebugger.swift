//
//  NotchSnapshotDebugger.swift
//  DynamicNotch
//
//  Prüfhilfe: Liegt die Datei snapshot-request im DynamicNotch-Ordner, speichert
//  die App ein Bild ihrer eigenen sichtbaren Fenster und rendert die
//  aufgeklappten Claude- und Quellen-Ansichten mit Live-Daten als PNG.
//  Eigene Fenster zu rendern braucht keine Bildschirmaufnahme-Berechtigung.
//

internal import AppKit
import ApplicationServices
import SwiftUI

@MainActor
enum NotchSnapshotDebugger {
    private static let directory = ClaudeActivityViewModel.stateDirectory.deletingLastPathComponent()
    private static let requestURL = directory.appendingPathComponent("snapshot-request")

    private static let commandRequestURL = directory.appendingPathComponent("media-command-request")
    private static let accessibilityURL = directory.appendingPathComponent("accessibility-trusted")

    /// Prüfhilfe für die Quellenliste: "media-command-request" enthält
    /// "<bundle-id> <befehl>" und wird ausgeführt wie ein Tipp in der Liste.
    /// "accessibility-trusted" zeigt, ob die Bedienungshilfen freigegeben sind.
    /// "open-request" aufklappen und Startseite zeigen, "close-request" zuklappen
    private static func handleOpenRequests(notch: NotchViewModel?) {
        guard let notch else { return }
        let openURL = directory.appendingPathComponent("open-request")
        let closeURL = directory.appendingPathComponent("close-request")
        if FileManager.default.fileExists(atPath: openURL.path) {
            // Optional steht der Seitenname drin, z. B. "localTimer"
            let pageName = (try? String(contentsOf: openURL, encoding: .utf8))?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            try? FileManager.default.removeItem(at: openURL)
            notch.handleActiveContentTap()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                if let page = HomePages(rawValue: pageName) {
                    NotchPageSwitcher.showSpecificHomePage(page)
                } else {
                    NotchPageSwitcher.showHomePage()
                }
            }
        }
        if FileManager.default.fileExists(atPath: closeURL.path) {
            try? FileManager.default.removeItem(at: closeURL)
            notch.handleOutsideClick()
        }
    }

    static func handleMediaRequests() {
        let trusted = AXIsProcessTrusted() ? "true" : "false"
        if (try? String(contentsOf: accessibilityURL, encoding: .utf8)) != trusted {
            try? trusted.write(to: accessibilityURL, atomically: true, encoding: .utf8)
        }

        // "ax-dump-request" mit einer Bundle-ID: alle Knöpfe dieser App nach ax-dump.txt
        let dumpRequestURL = directory.appendingPathComponent("ax-dump-request")
        if let bundleIdentifier = try? String(contentsOf: dumpRequestURL, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines) {
            try? FileManager.default.removeItem(at: dumpRequestURL)
            if let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).first {
                let pid = app.processIdentifier
                let outputURL = directory.appendingPathComponent("ax-dump.txt")
                Task.detached {
                    let lines = MediaSourcesAccessibility.dumpButtons(processIdentifier: pid)
                    try? ([bundleIdentifier] + lines).joined(separator: "\n")
                        .write(to: outputURL, atomically: true, encoding: .utf8)
                }
            }
        }

        guard let request = try? String(contentsOf: commandRequestURL, encoding: .utf8) else { return }
        try? FileManager.default.removeItem(at: commandRequestURL)

        let parts = request.split(separator: " ").map(String.init)
        guard parts.count == 2,
              let rawCommand = Int(parts[1].trimmingCharacters(in: .whitespacesAndNewlines)),
              let command = MediaSourceCommand(rawValue: rawCommand) else { return }

        let sources = MediaSourcesViewModel.shared
        Task {
            await sources.refresh()
            guard let source = sources.sources.first(where: { $0.bundleIdentifier == parts[0] }) else { return }
            sources.send(command, to: source)
        }
    }

    static func captureIfRequested(claude: ClaudeActivityViewModel) {
        handleMediaRequests()
        handleOpenRequests(notch: claude.notchViewModel)
        guard FileManager.default.fileExists(atPath: requestURL.path) else { return }
        try? FileManager.default.removeItem(at: requestURL)

        if let notch = claude.notchViewModel {
            let model = notch.notchModel
            let state = [
                "live: \(model.liveActivityContent?.id ?? "-")",
                "alert: \(model.alertContent?.id ?? "-")",
                "expanded: \(model.isExpanded)",
                "base: \(model.baseWidth)x\(model.baseHeight) size: \(model.size) presented: \(notch.presentedNotchSize)",
                "claude aktiv: \(claude.activeSessions.map(\.status))",
                "musik: \(claude.nowPlayingViewModel?.snapshot.map { "\($0.title) spielt=\($0.isPlaying)" } ?? "-")",
                "frontmost: \(NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "-")",
            ].joined(separator: "\n")
            write(Data(state.utf8), name: "notch-state.txt")
        }

        let windows = NSApp.windows.filter { $0.isVisible && $0.contentView != nil }
        for (index, window) in windows.enumerated() {
            guard let view = window.contentView,
                  let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { continue }
            view.cacheDisplay(in: view.bounds, to: bitmap)
            write(bitmap.representation(using: .png, properties: [:]), name: "snapshot-\(index).png")
        }

        if let nowPlaying = claude.nowPlayingViewModel {
            render(
                ClaudeExpandedNotchView(viewModel: claude, nowPlayingViewModel: nowPlaying),
                size: CGSize(width: 405, height: nowPlaying.snapshot == nil ? 145 : 190),
                name: "snapshot-claude-expanded.png"
            )
            render(
                ClaudeNotchView(viewModel: claude, nowPlayingViewModel: nowPlaying),
                size: CGSize(width: 335, height: 32),
                name: "snapshot-claude-compact.png"
            )
        }

        render(
            HStack(spacing: 10) {
                ForEach(CrabCostume.allCases, id: \.self) { costume in
                    ClaudeCrabView(costume: costume, isWalking: true, height: 56)
                }
            }
            .padding(12),
            size: CGSize(width: 480, height: 80),
            name: "snapshot-crabs.png"
        )

        let sources = MediaSourcesViewModel.shared
        Task {
            await sources.refresh()
            render(
                MediaSourcesListView(mediaSources: sources, currentBundleIdentifier: nil, onClose: {}),
                size: CGSize(width: 390, height: 195),
                name: "snapshot-sources.png"
            )
        }
    }

    private static func render<Content: View>(_ content: Content, size: CGSize, name: String) {
        let renderer = ImageRenderer(
            content: content
                .frame(width: size.width, height: size.height)
                .background(Color.black)
        )
        renderer.scale = 2
        guard let image = renderer.nsImage,
              let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff) else { return }
        write(bitmap.representation(using: .png, properties: [:]), name: name)
    }

    private static func write(_ data: Data?, name: String) {
        guard let data else { return }
        try? data.write(to: directory.appendingPathComponent(name))
    }
}
