//
//  MediaSourcesAccessibility.swift
//  DynamicNotch
//
//  Drückt den Play/Pause-Knopf einer App über die Bedienungshilfen, ohne sie
//  nach vorne zu holen. TIDAL und Pocket Casts (Electron) und die YouTube-App
//  (Chrome) bauen ihren Bedienungsbaum erst auf, wenn man danach fragt.
//

import ApplicationServices
import Foundation

enum MediaSourcesAccessibility {
    struct Candidate {
        let element: AXUIElement
        let label: String
        let y: CGFloat
    }

    /// Exakte Beschriftungen von Play/Pause-Knöpfen, klein geschrieben
    private static let exactLabels: Set<String> = [
        "play", "pause", "resume", "wiedergabe", "wiedergeben", "abspielen",
        "fortsetzen", "anhalten", "play/pause", "playpause", "play-pause",
    ]
    /// YouTube hängt die Taste an: "Wiedergabe (k)", "Pause (k)"
    private static let prefixLabels = ["play (", "pause (", "wiedergabe (", "wiedergeben ("]

    /// Sucht den Knopf und drückt ihn. Gibt die gedrückte Beschriftung zurück, sonst nil.
    nonisolated static func pressPlayPause(processIdentifier: pid_t) -> String? {
        let app = AXUIElementCreateApplication(processIdentifier)
        enableTree(of: app)

        for attempt in 0..<5 {
            if let best = candidates(in: app).max(by: { rank($0) < rank($1) }) {
                let result = AXUIElementPerformAction(best.element, kAXPressAction as CFString)
                return result == .success ? best.label : nil
            }
            // Chrome und Electron bauen den Baum beim ersten Mal erst nach etwa einer Sekunde auf
            if attempt < 4 { usleep(400_000) }
        }
        return nil
    }

    /// Schaltet den Bedienungsbaum vorab ein, damit der Knopf beim ersten Tippen schon da ist
    nonisolated static func prepare(processIdentifier: pid_t) {
        enableTree(of: AXUIElementCreateApplication(processIdentifier))
    }

    /// Für die Fehlersuche: alle Knöpfe mit Beschriftung und Höhe
    nonisolated static func dumpButtons(processIdentifier: pid_t) -> [String] {
        let app = AXUIElementCreateApplication(processIdentifier)
        enableTree(of: app)
        usleep(1_500_000)
        var lines: [String] = []
        walk(app, depth: 0) { element, role in
            guard role == kAXButtonRole as String else { return }
            let labels = labelsOf(element).joined(separator: " | ")
            lines.append("y=\(Int(positionY(of: element))) \(labels)")
        }
        return lines
    }

    // MARK: - Intern

    private nonisolated static func enableTree(of app: AXUIElement) {
        AXUIElementSetAttributeValue(app, "AXManualAccessibility" as CFString, kCFBooleanTrue)
        AXUIElementSetAttributeValue(app, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue)
    }

    private nonisolated static func candidates(in app: AXUIElement) -> [Candidate] {
        var found: [Candidate] = []
        walk(app, depth: 0) { element, role in
            guard role == kAXButtonRole as String else { return }
            for label in labelsOf(element) {
                let normalized = label.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
                if exactLabels.contains(normalized) || prefixLabels.contains(where: normalized.hasPrefix) {
                    found.append(Candidate(element: element, label: label, y: positionY(of: element)))
                    return
                }
            }
        }
        return found
    }

    /// Der Player sitzt unten im Fenster; YouTubes "(k)"-Knopf ist eindeutig
    private nonisolated static func rank(_ candidate: Candidate) -> CGFloat {
        candidate.label.contains("(k)") ? .greatestFiniteMagnitude : candidate.y
    }

    private nonisolated static func walk(
        _ element: AXUIElement,
        depth: Int,
        visit: (AXUIElement, String) -> Void
    ) {
        var budget = 6000
        walk(element, depth: depth, budget: &budget, visit: visit)
    }

    private nonisolated static func walk(
        _ element: AXUIElement,
        depth: Int,
        budget: inout Int,
        visit: (AXUIElement, String) -> Void
    ) {
        guard depth < 60, budget > 0 else { return }
        budget -= 1

        visit(element, stringAttribute(kAXRoleAttribute, of: element) ?? "")

        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &value) == .success,
              let children = value as? [AXUIElement] else { return }
        for child in children {
            walk(child, depth: depth + 1, budget: &budget, visit: visit)
        }
    }

    private nonisolated static func labelsOf(_ element: AXUIElement) -> [String] {
        [kAXDescriptionAttribute, kAXTitleAttribute, kAXHelpAttribute, kAXIdentifierAttribute, "AXDOMIdentifier"]
            .compactMap { stringAttribute($0, of: element) }
            .filter { !$0.isEmpty }
    }

    private nonisolated static func stringAttribute(_ name: String, of element: AXUIElement) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value as? String
    }

    private nonisolated static func positionY(of element: AXUIElement) -> CGFloat {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXValueGetTypeID() else { return 0 }
        var point = CGPoint.zero
        AXValueGetValue(value as! AXValue, .cgPoint, &point)
        return point.y
    }
}
