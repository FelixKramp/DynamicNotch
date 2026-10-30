//
//  MediaSourcesOverlayNotchContent.swift
//  DynamicNotch
//
//  Quellen-Liste als eigene Seite links von Claude bzw. dem Diktat. Eigenständig
//  statt über den Player, weil macOS den Player bei pausierter Musik nach einer
//  Weile aus dem Stapel nimmt; dann landete das Wischen sonst auf der Startseite.
//

import SwiftUI

extension NotchContentRegistry {
    enum MediaSourcesPage {
        // Nie von selbst vorne, nur angeheftet über Claude bzw. dem Diktat
        static let overlay = NotchContentDescriptor(id: "mediaSources.overlay", priority: -20000)
    }
}

struct MediaSourcesOverlayNotchContent: NotchContentProtocol, DynamicIslandCustomizable {
    let id = NotchContentRegistry.MediaSourcesPage.overlay.id
    let nowPlayingViewModel: NowPlayingViewModel

    var priority: Int { NotchContentRegistry.MediaSourcesPage.overlay.priority }
    var isExpandable: Bool { true }

    var strokeColor: Color {
        .white.opacity(0.12)
    }

    func size(baseWidth: CGFloat, baseHeight: CGFloat) -> CGSize {
        .init(width: baseWidth, height: baseHeight)
    }

    // So groß wie der Player, damit die Notch beim Wechsel nicht springt
    func expandedSize(baseWidth: CGFloat, baseHeight: CGFloat) -> CGSize {
        .init(width: baseWidth + 200, height: baseHeight + 160)
    }

    func expandedCornerRadius(baseRadius: CGFloat) -> (top: CGFloat, bottom: CGFloat) {
        (top: 34, bottom: 44)
    }

    func expandedDynamicIslandCornerRadius(baseHeight: CGFloat) -> CGFloat {
        baseHeight * 0.2
    }

    @MainActor
    func makeView() -> AnyView {
        AnyView(EmptyView())
    }

    @MainActor
    func makeExpandedView() -> AnyView {
        AnyView(MediaSourcesOverlayPageView(
            mediaSources: .shared,
            nowPlayingViewModel: nowPlayingViewModel
        ))
    }
}

/// Quellen ← Claude/Diktat → Startseite: nach links (oder „‹ Quellen“) geht es zurück
struct MediaSourcesOverlayPageView: View {
    @ObservedObject var mediaSources: MediaSourcesViewModel
    @ObservedObject var nowPlayingViewModel: NowPlayingViewModel

    var body: some View {
        MediaSourcesListView(
            mediaSources: mediaSources,
            currentBundleIdentifier: mediaSources.heldBundleIdentifier
                ?? nowPlayingViewModel.snapshot?.playbackSource?.preferredBundleIdentifier,
            onClose: { NotchPageSwitcher.returnToOverlay() }
        )
        .overlay(alignment: .bottom) {
            NotchOverlayPageDots(current: .sources).padding(.bottom, 3)
        }
        .onNotchHorizontalSwipe { direction in
            MediaSourcesViewModel.log("Quellen: \(direction == .left ? "links" : "rechts")")
            if direction == .left {
                NotchPageSwitcher.returnToOverlay()
            }
        }
        .onAppear {
            NotchPageSwitcher.debugPageSwipe = { direction in
                if direction == .left { NotchPageSwitcher.returnToOverlay() }
            }
        }
        .task {
            await mediaSources.refresh()
        }
    }
}
