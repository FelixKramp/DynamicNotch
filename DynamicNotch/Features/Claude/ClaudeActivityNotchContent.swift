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
    let sessionCount: Int

    var priority: Int { NotchContentRegistry.Claude.activity.priority }
    var isExpandable: Bool { true }

    var windowLink: (@MainActor () -> Void)? {
        { viewModel.openClaude() }
    }

    var strokeColor: Color {
        ClaudeStyle.accent.opacity(0.35)
    }

    /// Eine Krabbe mehr je weiterer Sitzung (18 pt hoch, also gut 19 pt breit)
    private var extraCrabWidth: CGFloat {
        CGFloat(max(0, min(sessionCount, ClaudeActivityViewModel.maxVisibleSessions) - 1)) * 21
    }

    /// Zwei Sitzungszeilen sind so hoch wie die Einzelansicht, jede weitere braucht mehr Platz
    private var extraListHeight: CGFloat {
        let rows = min(sessionCount, ClaudeActivityViewModel.maxVisibleSessions)
        return CGFloat(max(0, rows - 2)) * 45 + (sessionCount > ClaudeActivityViewModel.maxVisibleSessions ? 18 : 0)
    }

    func size(baseWidth: CGFloat, baseHeight: CGFloat) -> CGSize {
        // Links Krabben (+ Zählung), rechts Zählung oder Cover mit Equalizer
        .init(
            width: baseWidth + (isMusicPlaying ? 150 : 120) + extraCrabWidth + (DownloadViewModel.isDownloading ? 26 : 0),
            height: baseHeight
        )
    }

    func expandedSize(baseWidth: CGFloat, baseHeight: CGFloat) -> CGSize {
        .init(width: baseWidth + 220, height: baseHeight + (hasMusic ? 158 : 112) + extraListHeight)
    }

    func expandedDynamicIslandSize(baseWidth: CGFloat, baseHeight: CGFloat) -> CGSize {
        .init(width: baseWidth + 250, height: baseHeight + (hasMusic ? 148 : 102) + extraListHeight)
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
            .sink { [weak self] state in
                // Vor der Änderung gemeldet: den neuen Stand mitgeben statt snapshot zu lesen
                guard let self, !self.viewModel.activeSessions.isEmpty else { return }
                self.showActivity(music: state)
            }
            .store(in: &cancellables)

        // Kommt eine Sitzung dazu oder fällt weg, ändern sich Breite und Höhe
        viewModel.$activeSessions
            .map(\.count)
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] count in
                guard let self, count > 0 else { return }
                self.showActivity(sessionCount: count)
            }
            .store(in: &cancellables)

        viewModel.startMonitoring()
    }

    private struct MusicState: Equatable {
        let hasMusic: Bool
        let isPlaying: Bool
    }

    private func showActivity(music: MusicState? = nil, sessionCount: Int? = nil) {
        let snapshot = nowPlayingViewModel.snapshot
        let music = music ?? MusicState(hasMusic: snapshot != nil, isPlaying: snapshot?.isPlaying == true)
        notchViewModel.send(.showLiveActivity(ClaudeActivityNotchContent(
            viewModel: viewModel,
            nowPlayingViewModel: nowPlayingViewModel,
            isMusicPlaying: music.isPlaying,
            hasMusic: music.hasMusic,
            sessionCount: sessionCount ?? max(1, viewModel.activeSessions.count)
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
