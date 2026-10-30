//
//  ClaudeActivityNotchContent.swift
//  DynamicNotch
//

import Combine
import SwiftUI

extension NotchContentRegistry {
    enum Claude {
        // Über Musik (6) und Bildschirmaufnahme (9): Während Claude arbeitet, steht das vorne.
        // Die Musik verschwindet dabei nicht, sie läuft in derselben Anzeige mit.
        static let activity = NotchContentDescriptor(id: "claude.activity", priority: 15)
        static let finished = NotchContentDescriptor(id: "claude.finished", priority: 15)
    }
}

struct ClaudeActivityNotchContent: NotchContentProtocol, DynamicIslandCustomizable {
    let id = NotchContentRegistry.Claude.activity.id
    let viewModel: ClaudeActivityViewModel
    let nowPlayingViewModel: NowPlayingViewModel
    /// Beim Erstellen festgehalten; der Handler schickt die Anzeige neu, wenn sich das ändert
    let isMusicPlaying: Bool
    let hasMusic: Bool

    var priority: Int { NotchContentRegistry.Claude.activity.priority }
    var isExpandable: Bool { true }

    var windowLink: (@MainActor () -> Void)? {
        { viewModel.openClaude() }
    }

    var strokeColor: Color {
        ClaudeStyle.accent.opacity(0.35)
    }

    func size(baseWidth: CGFloat, baseHeight: CGFloat) -> CGSize {
        // Links Krabbe (+ Zählung), rechts Zählung oder Cover mit Equalizer
        .init(width: baseWidth + (isMusicPlaying ? 150 : 120) + (DownloadViewModel.isDownloading ? 26 : 0), height: baseHeight)
    }

    func expandedSize(baseWidth: CGFloat, baseHeight: CGFloat) -> CGSize {
        .init(width: baseWidth + 220, height: baseHeight + (hasMusic ? 158 : 112))
    }

    func expandedDynamicIslandSize(baseWidth: CGFloat, baseHeight: CGFloat) -> CGSize {
        .init(width: baseWidth + 250, height: baseHeight + (hasMusic ? 148 : 102))
    }

    func expandedCornerRadius(baseRadius: CGFloat) -> (top: CGFloat, bottom: CGFloat) {
        (top: 26, bottom: 36)
    }

    func expandedDynamicIslandCornerRadius(baseHeight: CGFloat) -> CGFloat {
        baseHeight * 0.4
    }

    @MainActor
    func makeView() -> AnyView {
        AnyView(ClaudeNotchView(viewModel: viewModel, nowPlayingViewModel: nowPlayingViewModel))
    }

    @MainActor
    func makeExpandedView() -> AnyView {
        AnyView(ClaudeExpandedNotchView(viewModel: viewModel, nowPlayingViewModel: nowPlayingViewModel))
    }
}

struct ClaudeFinishedNotchContent: NotchContentProtocol, DynamicIslandCustomizable {
    let id = NotchContentRegistry.Claude.finished.id
    let project: String

    var priority: Int { NotchContentRegistry.Claude.finished.priority }

    var strokeColor: Color {
        ClaudeStyle.accent.opacity(0.35)
    }

    func size(baseWidth: CGFloat, baseHeight: CGFloat) -> CGSize {
        .init(width: baseWidth + 130, height: baseHeight)
    }

    @MainActor
    func makeView() -> AnyView {
        AnyView(ClaudeFinishedNotchView(project: project))
    }
}

/// Zeigt und versteckt die Claude-Anzeige. Eigenständig, damit der Rest der
/// App nur eine Zeile dafür braucht.
@MainActor
final class NotchClaudeEventsHandler {
    private let notchViewModel: NotchViewModel
    private let nowPlayingViewModel: NowPlayingViewModel
    private let viewModel = ClaudeActivityViewModel()
    private var cancellables = Set<AnyCancellable>()

    init(notchViewModel: NotchViewModel, nowPlayingViewModel: NowPlayingViewModel) {
        self.notchViewModel = notchViewModel
        self.nowPlayingViewModel = nowPlayingViewModel
        viewModel.nowPlayingViewModel = nowPlayingViewModel
        viewModel.notchViewModel = notchViewModel
    }

    func start() {
        viewModel.$event
            .compactMap { $0 }
            .sink { [weak self] event in
                self?.handle(event)
            }
            .store(in: &cancellables)

        // Startet oder stoppt Musik, während Claude arbeitet, ändert sich die Breite
        nowPlayingViewModel.$snapshot
            .map { MusicState(hasMusic: $0 != nil, isPlaying: $0?.isPlaying == true) }
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] _ in
                guard let self, !self.viewModel.activeSessions.isEmpty else { return }
                self.showActivity()
            }
            .store(in: &cancellables)

        viewModel.startMonitoring()
    }

    private struct MusicState: Equatable {
        let hasMusic: Bool
        let isPlaying: Bool
    }

    private func showActivity() {
        let snapshot = nowPlayingViewModel.snapshot
        notchViewModel.send(.showLiveActivity(ClaudeActivityNotchContent(
            viewModel: viewModel,
            nowPlayingViewModel: nowPlayingViewModel,
            isMusicPlaying: snapshot?.isPlaying == true,
            hasMusic: snapshot != nil
        )))
    }

    private func handle(_ event: ClaudeActivityEvent) {
        switch event {
        case .started:
            showActivity()
        case .finished(let project):
            notchViewModel.send(.showTemporaryNotification(ClaudeFinishedNotchContent(project: project), duration: 2.5))
        case .stopped:
            notchViewModel.send(.hideLiveActivity(id: NotchContentRegistry.Claude.activity.id))
        }
    }
}
