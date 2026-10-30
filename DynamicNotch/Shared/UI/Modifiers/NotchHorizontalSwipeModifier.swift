//
//  NotchHorizontalSwipeModifier.swift
//  DynamicNotch
//
//  Zwei-Finger-Wischen nach links oder rechts über einer aufgeklappten Ansicht.
//  Das Wischen nach oben und unten (Ausblenden/Zurückholen) bleibt davon
//  unberührt, weil hier nur klar waagerechte Gesten zählen.
//

import SwiftUI
internal import AppKit

enum NotchHorizontalSwipeDirection {
    /// Finger bewegen sich nach links
    case left
    /// Finger bewegen sich nach rechts
    case right
}

extension View {
    func onNotchHorizontalSwipe(
        isEnabled: Bool = true,
        perform action: @escaping (NotchHorizontalSwipeDirection) -> Void
    ) -> some View {
        background(NotchHorizontalSwipeMonitorRepresentable(isEnabled: isEnabled, action: action))
    }
}

private struct NotchHorizontalSwipeMonitorRepresentable: NSViewRepresentable {
    let isEnabled: Bool
    let action: (NotchHorizontalSwipeDirection) -> Void

    func makeNSView(context: Context) -> NotchHorizontalSwipeMonitorView {
        let view = NotchHorizontalSwipeMonitorView()
        view.isEnabled = isEnabled
        view.action = action
        return view
    }

    func updateNSView(_ nsView: NotchHorizontalSwipeMonitorView, context: Context) {
        nsView.isEnabled = isEnabled
        nsView.action = action
    }

    static func dismantleNSView(_ nsView: NotchHorizontalSwipeMonitorView, coordinator: ()) {
        nsView.stopMonitoring()
    }
}

private final class NotchHorizontalSwipeMonitorView: NSView {
    private enum Metrics {
        /// So weit müssen die Finger waagerecht wandern, bevor die Seite wechselt
        static let threshold: CGFloat = 45
        /// Waagerecht muss deutlich überwiegen, sonst ist es ein Scrollen nach oben/unten
        static let dominance: CGFloat = 1.5
    }

    var isEnabled = true
    var action: ((NotchHorizontalSwipeDirection) -> Void)?

    private var localMonitor: Any?
    private var globalMonitor: Any?
    private var isTracking = false
    private var didTrigger = false
    private var horizontal: CGFloat = 0
    private var vertical: CGFloat = 0

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            stopMonitoring()
        } else {
            installMonitors()
        }
    }

    deinit {
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
    }

    func stopMonitoring() {
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        localMonitor = nil
        globalMonitor = nil
        reset()
    }

    private func installMonitors() {
        if localMonitor == nil {
            localMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                self?.process(event)
                return event
            }
        }
        if globalMonitor == nil {
            globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                self?.process(event)
            }
        }
    }

    private func process(_ event: NSEvent) {
        guard isEnabled, window != nil,
              event.hasPreciseScrollingDeltas,
              event.momentumPhase.isEmpty,
              !event.phase.isEmpty else { return }

        if event.phase.contains(.began) || event.phase.contains(.mayBegin) {
            reset()
            isTracking = isMouseInside
            return
        }
        if event.phase.contains(.ended) || event.phase.contains(.cancelled) {
            reset()
            return
        }
        guard isTracking, !didTrigger else { return }

        // Bei natürlichem Scrollen folgt der Inhalt den Fingern: Finger nach rechts
        // ergibt positives scrollingDeltaX. Ohne natürliches Scrollen ist es umgekehrt.
        let fingersRight = event.isDirectionInvertedFromDevice ? event.scrollingDeltaX : -event.scrollingDeltaX
        horizontal += fingersRight
        vertical += abs(event.scrollingDeltaY)

        guard abs(horizontal) >= Metrics.threshold,
              abs(horizontal) > vertical * Metrics.dominance else { return }

        didTrigger = true
        let direction: NotchHorizontalSwipeDirection = horizontal > 0 ? .right : .left
        MediaSourcesViewModel.log("Wischen \(direction == .right ? "rechts" : "links") (natürlich: \(event.isDirectionInvertedFromDevice))")
        DispatchQueue.main.async { [weak self] in
            self?.action?(direction)
        }
    }

    private var isMouseInside: Bool {
        guard let window else { return false }
        let frame = window.convertToScreen(convert(bounds, to: nil))
        return frame.contains(NSEvent.mouseLocation)
    }

    private func reset() {
        isTracking = false
        didTrigger = false
        horizontal = 0
        vertical = 0
    }
}

// MARK: - Seitenwechsel-Animation

/// Wie das Blättern zwischen Kamera und Timer: die Seite gleitet ein Stück zur Seite,
/// wird dabei unscharf und blendet aus.
private struct NotchPageSlideModifier: ViewModifier {
    let offset: CGFloat
    let blur: CGFloat
    let opacity: Double

    func body(content: Content) -> some View {
        content
            .offset(x: offset)
            .blur(radius: blur)
            .opacity(opacity)
    }
}

extension AnyTransition {
    static let notchPageAnimation = Animation.spring(response: 0.45, dampingFraction: 0.86)

    /// Seite, die beim Erscheinen von `insertionOffset` kommt und beim Verschwinden nach `removalOffset` geht
    static func notchPage(insertionOffset: CGFloat, removalOffset: CGFloat) -> AnyTransition {
        .asymmetric(
            insertion: .modifier(
                active: NotchPageSlideModifier(offset: insertionOffset, blur: 20, opacity: 0),
                identity: NotchPageSlideModifier(offset: 0, blur: 0, opacity: 1)
            ),
            removal: .modifier(
                active: NotchPageSlideModifier(offset: removalOffset, blur: 20, opacity: 0),
                identity: NotchPageSlideModifier(offset: 0, blur: 0, opacity: 1)
            )
        )
    }

    /// Seite, die immer an derselben Seite liegt (z. B. Quellen links vom Player)
    static func notchPage(edgeOffset: CGFloat) -> AnyTransition {
        notchPage(insertionOffset: edgeOffset, removalOffset: edgeOffset)
    }
}

// MARK: - Seitenpunkte

/// Zeigt, wo man in der Seitenreihe Quellen ← Player ← Claude/Diktat → Startseite steht,
/// solange Claude oder das Diktat die Notch belegt
struct NotchOverlayPageDots: View {
    enum Page: Int, CaseIterable {
        case sources, player, overlay, home
    }

    let current: Page

    var body: some View {
        HStack(spacing: 5) {
            ForEach(Page.allCases, id: \.self) { page in
                Capsule()
                    .fill(.white.opacity(page == current ? 0.85 : 0.25))
                    .frame(width: page == current ? 12 : 5, height: 5)
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: current)
        .allowsHitTesting(false)
    }
}
