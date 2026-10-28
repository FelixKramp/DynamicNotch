//
//  HomePageNotchView.swift
//  DynamicNotch
//
//  Created by Евгений Петрукович on 5/18/26.
//

import SwiftUI

struct HomePageNotchView: View {
    @Environment(\.isNotchlessScreen) var isNotchlessScreen
    
    let notchViewModel: NotchViewModel
    let settings: HomePageSettingsStore
    let localTimerViewModel: LocalTimerViewModel
    let nowPlayingViewModel: NowPlayingViewModel
    let mediaAndFilesSettings: MediaAndFilesSettingsStore
    let applicationSettings: ApplicationSettingsStore
    let initialPage: HomePages
    
    @State private var currentPage: HomePages?
    @State private var updateTask: Task<Void, Never>? = nil
    @State private var isWaitingForSizeUpdate = false
    @State private var isPageSettled = true
    @State private var settleTask: Task<Void, Never>? = nil
    // Ändern die Breite der Kamera-Seite, deshalb hier mitbeobachtet
    @AppStorage("isCameraStarted") private var isCameraStarted = false
    @AppStorage("isCameraLarge") private var isCameraLarge = false
    
    init(notchViewModel: NotchViewModel, settings: HomePageSettingsStore, localTimerViewModel: LocalTimerViewModel, nowPlayingViewModel: NowPlayingViewModel, mediaAndFilesSettings: MediaAndFilesSettingsStore, applicationSettings: ApplicationSettingsStore, initialPage: HomePages) {
        self.notchViewModel = notchViewModel
        self.settings = settings
        self.localTimerViewModel = localTimerViewModel
        self.nowPlayingViewModel = nowPlayingViewModel
        self.mediaAndFilesSettings = mediaAndFilesSettings
        self.applicationSettings = applicationSettings
        self.initialPage = initialPage
        
        let activePages = settings.homePageOrder.filter { !settings.homePageDisabled.contains($0) }
        let pageToSelect = activePages.contains(initialPage) ? initialPage : (activePages.first ?? .camera)
        self._currentPage = State(initialValue: pageToSelect)
    }
    
    var body: some View {
        let activePages = settings.homePageOrder.filter { !settings.homePageDisabled.contains($0) }
        let settled = isPageSettled
        
        VStack {
            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 20) {
                        ForEach(activePages) { page in
                            pageView(for: page)
                                // Jede Seite in ihrer eigenen Breite: sonst gibt die breiteste
                                // (Musik) allen anderen ihre Breite vor und die Kamera ragt
                                // über die Notch hinaus
                                .frame(width: pageWidth(for: page))
                                .containerRelativeFrame(.vertical)
                                .scrollTransition(.interactive) { content, phase in
                                    content
                                        .blur(radius: settled ? min(20, CGFloat(abs(phase.value)) * 150) : 20)
                                        .opacity(settled ? max(0.7, 1.0 - (abs(phase.value) * 2.0)) : 0.7)
                                }
                                .id(page)
                        }
                    }
                    .scrollTargetLayout()
                }
                .scrollTargetBehavior(.viewAligned)
                .scrollPosition(id: $currentPage, anchor: .top)
                .onAppear {
                    let targetPage = activePages.contains(initialPage) ? initialPage : (activePages.first ?? .camera)
                    currentPage = targetPage
                    updateLastPageStatus(page: targetPage, activePages: activePages)
                    proxy.scrollTo(targetPage, anchor: .top)

                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        proxy.scrollTo(targetPage, anchor: .top)
                    }
                }
                .onChange(of: notchViewModel.presentedNotchSize.height) { _, _ in
                    if let current = currentPage {
                        proxy.scrollTo(current, anchor: .top)
                    }
                }
                .onChange(of: initialPage) { _, newPage in
                    if newPage != currentPage && activePages.contains(newPage) {
                        currentPage = newPage
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                            proxy.scrollTo(newPage, anchor: .top)
                        }
                    }
                }
            }
            .mask {
                if !isNotchlessScreen && !notchViewModel.isDynamicIsland {
                    let baseHeight = notchViewModel.notchModel.baseHeight
                    let cornerRadius: CGFloat = 30
                    
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .mask(
                            VStack(spacing: 0) {
                                Color.clear
                                    .frame(height: baseHeight)
                                LinearGradient(
                                    stops: [
                                        .init(color: .clear, location: 0),
                                        .init(color: .black, location: 1)
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                                .frame(height: 4)
                                Color.black
                            }
                        )
                } else {
                    Color.black
                }
            }
        }
        .onNotchHorizontalSwipe(isEnabled: currentPage != .mediaPlayer) { direction in
            guard direction == .right else { return }
            // Über laufender Musik geöffnet: zurück zum Player. Sonst zur Musik-Seite.
            if notchViewModel.isShowingPinnedLiveActivity {
                NotchPageSwitcher.returnFromHomePage()
            } else if activePages.contains(.mediaPlayer) {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                    currentPage = .mediaPlayer
                }
            }
        }
        .onChange(of: activePages) { _, newActivePages in
            let updatedPage: HomePages?
            if let current = currentPage, !newActivePages.contains(current) {
                let first = newActivePages.first
                currentPage = first
                updatedPage = first
            } else {
                updatedPage = currentPage
            }
            updateLastPageStatus(page: updatedPage, activePages: newActivePages)
        }
        .onChange(of: currentPage) { oldPage, newPage in
            updateLastPageStatus(page: newPage, activePages: activePages)
            guard let oldPage = oldPage, let newPage = newPage, newPage != oldPage else { return }
            
            withAnimation(.easeInOut(duration: 0.15)) {
                isWaitingForSizeUpdate = true
            }
            
            isPageSettled = false
            settleTask?.cancel()
            settleTask = Task {
                try? await Task.sleep(nanoseconds: 500_000_000)
                guard !Task.isCancelled else { return }
                withAnimation(.spring(response: 0.5)) {
                    isPageSettled = true
                }
            }
            
            updateTask?.cancel()
            updateTask = Task {
                try? await Task.sleep(nanoseconds: 300_000_000)
                guard !Task.isCancelled else { return }
                
                notchViewModel.send(
                    .showLiveActivity(
                        HomePageNotchContent(
                            notchViewModel: notchViewModel,
                            settings: settings,
                            homePages: newPage,
                            localTimerViewModel: localTimerViewModel,
                            nowPlayingViewModel: nowPlayingViewModel,
                            mediaAndFilesSettings: mediaAndFilesSettings,
                            applicationSettings: applicationSettings
                        )
                    )
                )
                
                withAnimation(.easeInOut(duration: 0.35)) {
                    isWaitingForSizeUpdate = false
                }
            }
        }
        .onDisappear {
            notchViewModel.isHomePageOnLastPage = false
            let activePages = settings.homePageOrder.filter { !settings.homePageDisabled.contains($0) }
            notchViewModel.send(
                .showLiveActivity(
                    HomePageNotchContent(
                        notchViewModel: notchViewModel,
                        settings: settings,
                        homePages: activePages.first ?? .camera,
                        localTimerViewModel: localTimerViewModel,
                        nowPlayingViewModel: nowPlayingViewModel,
                        mediaAndFilesSettings: mediaAndFilesSettings,
                        applicationSettings: applicationSettings
                    )
                )
            )
            settleTask?.cancel()
            updateTask?.cancel()
        }
    }
    
    private func pageWidth(for page: HomePages) -> CGFloat? {
        let model = notchViewModel.notchModel
        guard model.baseWidth > 0 else { return nil }
        let content = HomePageNotchContent(
            notchViewModel: notchViewModel,
            settings: settings,
            homePages: page,
            localTimerViewModel: localTimerViewModel,
            nowPlayingViewModel: nowPlayingViewModel,
            mediaAndFilesSettings: mediaAndFilesSettings,
            applicationSettings: applicationSettings
        )
        let size = model.isDynamicIsland
            ? content.expandedDynamicIslandSize(baseWidth: model.baseWidth, baseHeight: model.baseHeight)
            : content.expandedSize(baseWidth: model.baseWidth, baseHeight: model.baseHeight)
        return size.width
    }

    private func showPage(after page: HomePages) {
        let activePages = settings.homePageOrder.filter { !settings.homePageDisabled.contains($0) }
        guard let index = activePages.firstIndex(of: page), index + 1 < activePages.count else { return }
        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
            currentPage = activePages[index + 1]
        }
    }

    private func updateLastPageStatus(page: HomePages?, activePages: [HomePages]) {
        let isLast = page != nil && page == activePages.last
        if notchViewModel.isHomePageOnLastPage != isLast {
            notchViewModel.isHomePageOnLastPage = isLast
        }
    }
    
    @ViewBuilder
    private func pageView(for page: HomePages) -> some View {
        switch page {
        case .mediaPlayer:
            NowPlayingExpandedNotchView(
                nowPlayingViewModel: nowPlayingViewModel,
                settings: mediaAndFilesSettings,
                applicationSettings: applicationSettings,
                onOpenPlaybackSource: { nowPlayingViewModel.openPlaybackSource() },
                onSwipeLeft: { showPage(after: .mediaPlayer) },
                isSwipeEnabled: currentPage == .mediaPlayer
            )
        case .camera:
            CameraNotchView(notchViewModel: notchViewModel, settings: settings, localTimerViewModel: localTimerViewModel, nowPlayingViewModel: nowPlayingViewModel, mediaAndFilesSettings: mediaAndFilesSettings, applicationSettings: applicationSettings)
        case .localTimer:
            LocalTimerSetupNotchView(localTimerViewModel: localTimerViewModel)
        case .vpn:
            VpnPageNotchView(notchViewModel: notchViewModel)
        }
    }
}
