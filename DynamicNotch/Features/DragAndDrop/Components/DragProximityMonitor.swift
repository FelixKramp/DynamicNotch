//
//  DragProximityMonitor.swift
//  DynamicNotch
//
//  Öffnet die Ablagefelder schon, wenn eine Datei in die Nähe der Notch gezogen
//  wird. Sonst muss man bis an den oberen Bildschirmrand ziehen, und dort öffnet
//  macOS Mission Control mit der Schreibtisch-Leiste.
//

internal import AppKit

@MainActor
final class DragProximityMonitor {
    /// Abstand zur Bildschirmoberkante und zur Mitte, ab dem die Felder aufgehen
    private static let openDistance = CGSize(width: 320, height: 170)
    /// Erst weiter weg gehen sie wieder zu, damit sie am Rand nicht flackern
    private static let closeDistance = CGSize(width: 420, height: 260)

    private let airDropViewModel: AirDropNotchViewModel
    private var monitors: [Any] = []
    private var changeCountAtMouseDown = NSPasteboard(name: .drag).changeCount
    private var openedByProximity = false

    /// Für die Prüfhilfe (NotchSnapshotDebugger)
    static weak var airDropViewModel: AirDropNotchViewModel?

    init(airDropViewModel: AirDropNotchViewModel) {
        self.airDropViewModel = airDropViewModel
        Self.airDropViewModel = airDropViewModel
    }

    func start() {
        guard monitors.isEmpty else { return }

        let handlers: [(NSEvent.EventTypeMask, @MainActor (DragProximityMonitor) -> Void)] = [
            (.leftMouseDown, { $0.mouseDown() }),
            (.leftMouseDragged, { $0.mouseDragged() }),
            (.leftMouseUp, { $0.mouseUp() }),
        ]
        for (mask, handler) in handlers {
            if let monitor = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    handler(self)
                }
            }) {
                monitors.append(monitor)
            }
        }
    }

    private func mouseDown() {
        changeCountAtMouseDown = NSPasteboard(name: .drag).changeCount
    }

    private func mouseDragged() {
        // Nur echte Datei-Ziehvorgänge: die Zieh-Ablage wurde seit dem Klick neu befüllt
        let pasteboard = NSPasteboard(name: .drag)
        guard pasteboard.changeCount != changeCountAtMouseDown,
              pasteboard.types?.contains(.fileURL) == true else { return }

        let location = NSEvent.mouseLocation
        if !airDropViewModel.isDraggingFile, isNearNotch(location, within: Self.openDistance) {
            openedByProximity = true
            airDropViewModel.setDraggingFile(true)
        } else if openedByProximity,
                  !airDropViewModel.isDropZoneTargeted,
                  !isNearNotch(location, within: Self.closeDistance) {
            openedByProximity = false
            airDropViewModel.setDraggingFile(false)
        }
    }

    private func mouseUp() {
        guard openedByProximity else { return }
        openedByProximity = false

        // Wurde in ein Feld abgelegt, räumt die Ablage selbst auf. Sonst hier schließen,
        // mit kurzer Pause, damit ein laufender Drop nicht unterbrochen wird.
        Task { [airDropViewModel] in
            try? await Task.sleep(for: .milliseconds(500))
            if airDropViewModel.isDraggingFile, !airDropViewModel.isDropZoneTargeted {
                airDropViewModel.setDraggingFile(false)
            }
        }
    }

    private func isNearNotch(_ location: NSPoint, within distance: CGSize) -> Bool {
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(location) }) else { return false }
        let fromTop = screen.frame.maxY - location.y
        let fromCenter = abs(location.x - screen.frame.midX)
        return fromTop < distance.height && fromCenter < distance.width
    }
}
