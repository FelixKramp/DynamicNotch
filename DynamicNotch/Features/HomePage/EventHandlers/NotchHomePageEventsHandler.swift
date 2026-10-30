//
//  NotchHomePageEventsHandler.swift
//  DynamicNotch
//
//  Created by Евгений Петрукович on 5/18/26.
//

import SwiftUI

enum HomePageEvent: Equatable {
    case homePageOn
    case homePageOff
}

@MainActor
final class NotchHomePageEventsHandler {
    private let notchViewModel: NotchViewModel
    private let settingsViewModel: SettingsViewModel
    private let localTimerViewModel: LocalTimerViewModel
    private let nowPlayingViewModel: NowPlayingViewModel

    init(
        notchViewModel: NotchViewModel,
        settingsViewModel: SettingsViewModel,
        localTimerViewModel: LocalTimerViewModel,
        nowPlayingViewModel: NowPlayingViewModel
    ) {
        self.notchViewModel = notchViewModel
        self.settingsViewModel = settingsViewModel
        self.localTimerViewModel = localTimerViewModel
        self.nowPlayingViewModel = nowPlayingViewModel

        NotchPageSwitcher.showHomePage = { [weak self] in self?.showHomePageOverActivity() }
        NotchPageSwitcher.showSpecificHomePage = { [weak self] page in self?.showHomePageOverActivity(preferred: page) }
        NotchPageSwitcher.returnFromHomePage = { [weak notchViewModel] in notchViewModel?.releasePinnedLiveActivity() }
        NotchPageSwitcher.showPlayer = { [weak self] in
            // Kein Player im Stapel (z. B. Musik pausiert): die Musik-Seite der Startseite
            guard let self, !self.notchViewModel.presentPinnedPlayer() else { return }
            self.showHomePageOverActivity(preferred: .mediaPlayer)
        }
    }

    /// Mod: Startseite (Kamera, Timer, VPN) zeigen, obwohl gerade Musik läuft.
    /// Beim Zuklappen kommt der Player von selbst wieder nach vorne.
    private func showHomePageOverActivity(preferred: HomePages? = nil) {
        let activePages = settingsViewModel.homePage.homePageOrder.filter { !settingsViewModel.homePage.homePageDisabled.contains($0) }
        let fallback = activePages.first(where: { $0 != .mediaPlayer }) ?? activePages.first
        guard let page = preferred.flatMap({ activePages.contains($0) ? $0 : nil }) ?? fallback else { return }
        notchViewModel.presentPinnedExpanded(HomePageNotchContent(
            notchViewModel: notchViewModel,
            settings: settingsViewModel.homePage,
            homePages: page,
            localTimerViewModel: localTimerViewModel,
            nowPlayingViewModel: nowPlayingViewModel,
            mediaAndFilesSettings: settingsViewModel.mediaAndFiles,
            applicationSettings: settingsViewModel.application
        ))
    }
    
    func handleHomePage(_ event: HomePageEvent) {
        switch event {
        case .homePageOn:
            let activePages = settingsViewModel.homePage.homePageOrder.filter { !settingsViewModel.homePage.homePageDisabled.contains($0) }
            let activePage = activePages.first ?? .camera
            notchViewModel.send(.showLiveActivity(HomePageNotchContent(
                notchViewModel: notchViewModel,
                settings: settingsViewModel.homePage,
                homePages: activePage,
                localTimerViewModel: localTimerViewModel,
                nowPlayingViewModel: nowPlayingViewModel,
                mediaAndFilesSettings: settingsViewModel.mediaAndFiles,
                applicationSettings: settingsViewModel.application
            )))
            
        case .homePageOff:
            notchViewModel.send(.hideLiveActivity(id: NotchContentRegistry.HomePage.active.id))
        }
    }
}

/// Mod: Seitenwechsel per Wischen zwischen Player und Startseite
@MainActor
enum NotchPageSwitcher {
    static var showHomePage: () -> Void = {}
    static var returnFromHomePage: () -> Void = {}
    static var showSpecificHomePage: (HomePages) -> Void = { _ in }
    static var showPlayer: () -> Void = {}

    /// Claude und Diktat belegen die aufgeklappte Notch: rechts holt den Player, links die Startseite
    static func handleOverlaySwipe(_ direction: NotchHorizontalSwipeDirection) {
        switch direction {
        case .right: showPlayer()
        case .left: showHomePage()
        }
    }
}
