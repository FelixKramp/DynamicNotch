//
//  BlipService.swift
//  DynamicNotch
//
//  Übergibt Dateien an Blip (blip.net, auch für Android). Blip bietet dafür
//  den macOS-Dienst "Blip…" an, derselbe Weg wie Rechtsklick > Dienste.
//

internal import AppKit

enum BlipService {
    static let bundleIdentifier = "net.blip.macos"
    /// Name aus NSServices in Blips Info.plist, mit echtem Auslassungszeichen
    private static let serviceName = "Blip\u{2026}"

    static var isAvailable: Bool {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) != nil
    }

    static var appIcon: NSImage? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier)
            .map { NSWorkspace.shared.icon(forFile: $0.path) }
    }

    /// Liest die Dateien aus der Ablage des Ziehvorgangs und reicht sie an Blip weiter
    static func send(_ pasteboard: NSPasteboard) -> Bool {
        let urls = pasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL] ?? []
        guard !urls.isEmpty, isAvailable else { return false }

        let servicePasteboard = NSPasteboard(name: NSPasteboard.Name("DynamicNotch.Blip.\(UUID().uuidString)"))
        servicePasteboard.clearContents()
        guard servicePasteboard.writeObjects(urls as [NSURL]) else { return false }
        return NSPerformService(serviceName, servicePasteboard)
    }
}
