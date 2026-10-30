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
    /// "open-request" aufklappen und Startseite zeigen, "close-request" zuklappen,
    /// "airdrop-request" mit complete/fail/cancel spielt eine AirDrop-Übertragung durch
    private static func handleOpenRequests(notch: NotchViewModel?) {
        guard let notch else { return }
        let airDropURL = directory.appendingPathComponent("airdrop-request")
        if let mode = try? String(contentsOf: airDropURL, encoding: .utf8),
           let airDrop = DragProximityMonitor.airDropViewModel {
            try? FileManager.default.removeItem(at: airDropURL)
            let id = UUID()
            airDrop.beginTransfer(id: id, urls: [URL(fileURLWithPath: "/tmp/test.pdf")])
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                switch mode.trimmingCharacters(in: .whitespacesAndNewlines) {
                case "fail": airDrop.failTransfer(id: id, error: NSError(domain: "Test", code: 1))
                case "cancel": airDrop.cancelTransfer(id: id)
                default: airDrop.completeTransfer(id: id)
                }
            }
        }
        let openURL = directory.appendingPathComponent("open-request")
        let closeURL = directory.appendingPathComponent("close-request")
        if FileManager.default.fileExists(atPath: openURL.path) {
            // Optional steht der Seitenname drin, z. B. "localTimer"
            let pageName = (try? String(contentsOf: openURL, encoding: .utf8))?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            try? FileManager.default.removeItem(at: openURL)
            notch.handleActiveContentTap()
            // "expand": nur aufklappen, ohne Startseite davor
            guard pageName != "expand" else { return }
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
        // "click-request" mit "x y" (Bildschirmpunkte, oben links 0/0): Klick direkt an das Notch-Fenster
        let clickURL = directory.appendingPathComponent("click-request")
        if let text = try? String(contentsOf: clickURL, encoding: .utf8) {
            try? FileManager.default.removeItem(at: clickURL)
            let parts = text.split(separator: " ").compactMap { Double($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
            if parts.count == 2, let screen = NSScreen.screens.first {
                let point = NSPoint(x: parts[0], y: screen.frame.maxY - parts[1])
                if let window = NSApp.windows.first(where: { $0.isVisible && $0.frame.contains(point) && $0.level.rawValue > 0 }) {
                    let location = window.convertPoint(fromScreen: point)
                    for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
                        if let event = NSEvent.mouseEvent(
                            with: type, location: location, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                            windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1
                        ) {
                            window.sendEvent(event)
                        }
                    }
                }
            }
        }

        // "open-app-request" mit claude oder musik: dieselben Aktionen wie die Knöpfe der Übersicht
        let openAppURL = directory.appendingPathComponent("open-app-request")
        if let target = try? String(contentsOf: openAppURL, encoding: .utf8) {
            try? FileManager.default.removeItem(at: openAppURL)
            if target.hasPrefix("claude") {
                claude.openClaude()
            } else {
                claude.nowPlayingViewModel?.openPlaybackSource()
            }
        }
        // "whisperbar-request" mit show/hide (Anzeige ohne Aufnahme), finish oder cancel (echte Befehle an WhisperBar)
        let whisperURL = directory.appendingPathComponent("whisperbar-request")
        if let command = try? String(contentsOf: whisperURL, encoding: .utf8) {
            try? FileManager.default.removeItem(at: whisperURL)
            switch command.trimmingCharacters(in: .whitespacesAndNewlines) {
            case "show": NotchWhisperBarEventsHandler.current?.debugShow(true)
            case "hide": NotchWhisperBarEventsHandler.current?.debugShow(false)
            case "finish": WhisperBarRemote.finish()
            case "cancel": WhisperBarRemote.cancel()
            case "finish-test":
                // Wie ein Klick auf "Fertig": Das Notch-Panel übernimmt die Tastatur, ohne dass
                // DynamicNotch aktiv wird. Danach muss die Tastatur zurück bei der vorigen App sein.
                let logURL = directory.appendingPathComponent("whisperbar-finish-test.txt")
                NSApp.windows.first { $0 is OverlayPanelWindow && $0.isVisible }?.makeKey()
                let before = "Panel hat Tastatur: \(NSApp.keyWindow != nil), vorne: \(NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "-")"
                WhisperBarRemote.finish()
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                    let after = "danach Panel hat Tastatur: \(NSApp.keyWindow != nil), vorne: \(NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "-")"
                    try? [before, after].joined(separator: "\n").write(to: logURL, atomically: true, encoding: .utf8)
                }
            case "paste-test":
                // Ganzer Ablauf: eigenes Testfenster mit Textfeld, Aufnahme starten, nach 3 s
                // "Fertig". Protokolliert nur die Zeichenzahl, nicht den Text.
                let previous = NSWorkspace.shared.frontmostApplication
                let logURL = directory.appendingPathComponent("whisperbar-paste-test.txt")
                let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 360, height: 80),
                                      styleMask: [.titled], backing: .buffered, defer: false)
                window.title = "WhisperBar-Test"
                window.isReleasedWhenClosed = false
                let field = NSTextField(frame: NSRect(x: 20, y: 25, width: 320, height: 30))
                window.contentView?.addSubview(field)
                window.center()
                NSApp.activate(ignoringOtherApps: true)
                window.makeKeyAndOrderFront(nil)
                window.makeFirstResponder(field)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    WhisperBarRemote.finish()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                        WhisperBarRemote.finish()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
                            let lines = [
                                "vorne: \(NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "-")",
                                "eingefügte Zeichen: \(field.stringValue.count)",
                            ]
                            try? lines.joined(separator: "\n").write(to: logURL, atomically: true, encoding: .utf8)
                            window.close()
                            previous?.activate()
                        }
                    }
                }
            case "tuck":
                if let pid = NSRunningApplication.runningApplications(withBundleIdentifier: WhisperBarMonitor.bundleIdentifier).first?.processIdentifier {
                    let centerX = NSScreen.screens.first?.frame.midX ?? 735
                    let logURL = directory.appendingPathComponent("whisperbar-tuck.txt")
                    Task.detached {
                        let log = WhisperBarRemote.tuckOverlayUnderNotch(processIdentifier: pid, notchCenterX: centerX, notchHeight: 36)
                        try? log.joined(separator: "\n").write(to: logURL, atomically: true, encoding: .utf8)
                    }
                }
            default: break
            }
        }
        // "swipe-request" mit left/right: wie Wischen in der Claude- bzw. Diktat-Ansicht
        let swipeURL = directory.appendingPathComponent("swipe-request")
        if let direction = try? String(contentsOf: swipeURL, encoding: .utf8) {
            try? FileManager.default.removeItem(at: swipeURL)
            let trimmed = direction.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasPrefix("player-") {
                NotchPageSwitcher.debugPlayerSwipe?(trimmed.hasSuffix("left") ? .left : .right)
            } else {
                NotchPageSwitcher.handleOverlaySwipe(trimmed.hasPrefix("left") ? .left : .right)
            }
        }
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
                "stapel: \(notch.debugActiveLiveActivityIDs)",
                "airdrop: \(DragProximityMonitor.airDropViewModel?.activeTransfer.map { "\($0.status)" } ?? "-") ziehen=\(DragProximityMonitor.airDropViewModel?.isDraggingFile ?? false)",
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
            // Kleine Musik-Anzeige, mit Download-Ring falls gerade einer läuft
            render(
                NowPlayingMinimalNotchView(
                    nowPlayingViewModel: nowPlaying,
                    settings: MediaAndFilesSettingsStore(defaults: .standard)
                )
                .background(.black),
                size: CGSize(width: DownloadViewModel.isDownloading ? 315 : 285, height: 36),
                name: "snapshot-music-compact.png"
            )
        }

        render(
            VStack(alignment: .leading, spacing: 14) {
                ForEach([Array(CrabCostume.allCases.prefix(8)), Array(CrabCostume.allCases.dropFirst(8))], id: \.self) { row in
                    HStack(spacing: 10) {
                        ForEach(row, id: \.self) { costume in
                            ClaudeCrabView(costume: costume, isWalking: true, height: 56)
                        }
                    }
                }
            }
            .padding(12),
            size: CGSize(width: 540, height: 160),
            name: "snapshot-crabs.png"
        )

        if let nowPlaying = claude.nowPlayingViewModel {
            render(
                WhisperBarExpandedNotchView(startedAt: .now.addingTimeInterval(-23), nowPlayingViewModel: nowPlaying, levelMeter: MicLevelMeter()),
                size: CGSize(width: 385, height: nowPlaying.snapshot == nil ? 150 : 196),
                name: "snapshot-whisperbar-expanded.png"
            )
        }

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
