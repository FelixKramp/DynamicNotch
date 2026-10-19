//
//  WindowSnapPreviewManager.swift
//  DynamicNotch
//

internal import AppKit
import SwiftUI

private final class WindowSnapPreviewPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private struct WindowSnapPreviewView: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(nsColor: .black).opacity(0.16))

            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color(nsColor: .white).opacity(0.6), lineWidth: 3)
                .shadow(color: .black.opacity(0.6), radius: 6)
        }
    }
}

@MainActor
final class WindowSnapPreviewManager {
    private var panel: WindowSnapPreviewPanel?
    private var isShowing = false
    private var currentTargetFrame: NSRect = .zero

    func show(targetFrame: NSRect) {
        let p: WindowSnapPreviewPanel
        if let existing = panel {
            p = existing
        } else {
            let newPanel = WindowSnapPreviewPanel(
                contentRect: targetFrame,
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            newPanel.isOpaque = false
            newPanel.backgroundColor = .clear
            newPanel.hasShadow = false
            newPanel.isFloatingPanel = true
            newPanel.level = .floating
            newPanel.ignoresMouseEvents = true
            newPanel.hidesOnDeactivate = false
            newPanel.isMovable = false
            newPanel.animationBehavior = .none
            newPanel.collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle, .fullScreenAuxiliary]
            newPanel.contentView = NSHostingView(rootView: WindowSnapPreviewView())
            self.panel = newPanel
            p = newPanel
        }

        if currentTargetFrame != targetFrame {
            currentTargetFrame = targetFrame
            p.setFrame(targetFrame, display: true)
        }

        guard !isShowing else { return }
        isShowing = true

        p.alphaValue = 0.0
        p.orderFrontRegardless()

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.14
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            p.animator().alphaValue = 1.0
        }
    }

    func hide(animated: Bool = true) {
        guard isShowing, let panel else { return }
        isShowing = false
        currentTargetFrame = .zero

        if animated {
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.12
                context.timingFunction = CAMediaTimingFunction(name: .easeIn)
                panel.animator().alphaValue = 0.0
            }, completionHandler: { [weak self] in
                MainActor.assumeIsolated {
                    guard let self, !self.isShowing else { return }
                    self.panel?.orderOut(nil)
                }
            })
        } else {
            panel.alphaValue = 0.0
            panel.orderOut(nil)
        }
    }

    func hideImmediately() {
        hide(animated: false)
    }
}
