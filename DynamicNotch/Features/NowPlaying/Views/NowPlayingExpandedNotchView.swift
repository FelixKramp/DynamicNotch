//
//  NowPlayingExpandedNotchView.swift
//  DynamicNotch
//
//  Created by Евгений Петрукович on 4/14/26.
//

import SwiftUI

struct NowPlayingExpandedNotchView: View {
    @Environment(\.notchScale) var scale
    @Environment(\.isNotchlessScreen) var isNotchlessScreen
    
    @ObservedObject var nowPlayingViewModel: NowPlayingViewModel
    @ObservedObject var settings: MediaAndFilesSettingsStore
    @ObservedObject var applicationSettings: ApplicationSettingsStore
    
    let onOpenPlaybackSource: @MainActor () -> Void
    /// Wischen nach links: standardmäßig die Startseite mit Kamera, Timer, VPN
    var onSwipeLeft: (@MainActor () -> Void)? = nil
    var isSwipeEnabled = true
    
    @State private var scrubProgress: CGFloat?
    @State private var showsMediaSources = false
    @ObservedObject private var mediaSources = MediaSourcesViewModel.shared
    private let detailedPresentationSource = "nowPlaying.notch.expanded"
    
    /// macOS meldet nur eine App als aktiv. Wird die pausiert, während eine andere weiterläuft
    /// (Pocket Casts spielt, TIDAL kurz an und wieder aus), bleibt sie trotzdem die aktive.
    /// Dann zeigt und steuert die Karte die Quelle, die wirklich spielt.
    private var playingOtherSource: MediaSource? {
        guard nowPlayingViewModel.snapshot?.isPlaying != true else { return nil }
        let reported = nowPlayingViewModel.snapshot?.playbackSource?.preferredBundleIdentifier
        let others = mediaSources.sources.filter { $0.bundleIdentifier != reported }
        return others.first(where: \.isPlaying)
            ?? others.first { $0.bundleIdentifier == mediaSources.heldBundleIdentifier }
    }

    private var resolvedSnapshot: NowPlayingSnapshot {
        if let playingOtherSource {
            return playingOtherSource.makeSnapshot()
        }
        return nowPlayingViewModel.snapshot ?? NowPlayingSnapshot(
            title: "Gerade läuft nichts",
            artist: "Starte Musik in TIDAL, YouTube oder Pocket Casts",
            album: "Debug Preview",
            duration: 0,
            elapsedTime: 0,
            playbackRate: 0,
            artworkData: nil,
            refreshedAt: .now
        )
    }
    
    var body: some View {
        let snapshot = resolvedSnapshot

        return ZStack {
            if showsMediaSources {
                MediaSourcesListView(
                    mediaSources: mediaSources,
                    currentBundleIdentifier: playingOtherSource?.bundleIdentifier
                        ?? nowPlayingViewModel.snapshot?.playbackSource?.preferredBundleIdentifier,
                    onClose: { toggleMediaSources() }
                )
                // Quellen liegen links vom Player
                .transition(.notchPage(edgeOffset: -90))
            } else {
                TimelineView(.periodic(from: .now, by: progressTick(for: snapshot))) { context in
                    timelineContent(snapshot: snapshot, at: context.date)
                }
                .transition(.notchPage(edgeOffset: 90))
            }
        }
        .onChange(of: playingOtherSource?.bundleIdentifier) { _, bundleIdentifier in
            mediaSources.heldBundleIdentifier = bundleIdentifier
        }
        .onNotchHorizontalSwipe(isEnabled: isSwipeEnabled) { direction in
            handleSwipe(direction)
        }
        .onAppear {
            mediaSources.startObserving()
            nowPlayingViewModel.setDetailedPresentationActive(
                true,
                source: detailedPresentationSource
            )
        }
        .onDisappear {
            mediaSources.stopObserving()
            showsMediaSources = false
            nowPlayingViewModel.setDetailedPresentationActive(
                false,
                source: detailedPresentationSource
            )
        }
    }

    private var currentSource: MediaSource? {
        if let playingOtherSource { return playingOtherSource }
        let bundleIdentifier = nowPlayingViewModel.snapshot?.playbackSource?.preferredBundleIdentifier
        return mediaSources.sources.first { $0.bundleIdentifier == bundleIdentifier }
            ?? mediaSources.sources.first(where: \.isNowPlaying)
    }

    /// "TIDAL · 3 ⌄" über dem Titel: zeigt die aktive Quelle und ist der einzige Weg zur Liste
    private var sourcePill: some View {
        Button(action: toggleMediaSources) {
            HStack(spacing: 4) {
                if let source = currentSource, let icon = mediaSources.icon(for: source) {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: 13, height: 13)
                }
                Text(currentSource?.name ?? "Quellen")
                    .font(.system(size: 11, weight: .semibold))
                    .lineLimit(1)
                Text("· \(mediaSources.sources.count)")
                    .font(.system(size: 11, weight: .semibold).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.55))
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .bold))
            }
            .foregroundStyle(.white.opacity(0.85))
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(Capsule().fill(.white.opacity(0.14)))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help("Zwischen Quellen wechseln")
    }

    /// Seitenreihe: Quellen ← Player → Startseite
    private func handleSwipe(_ direction: NotchHorizontalSwipeDirection) {
        switch direction {
        case .right where !showsMediaSources:
            toggleMediaSources()
        case .left where showsMediaSources:
            toggleMediaSources()
        case .left:
            (onSwipeLeft ?? NotchPageSwitcher.showHomePage)()
        case .right:
            break
        }
    }

    private func toggleMediaSources() {
        withAnimation(AnyTransition.notchPageAnimation) {
            showsMediaSources.toggle()
        }
    }

    private func timelineContent(snapshot: NowPlayingSnapshot, at date: Date) -> some View {
        let elapsedTime = nowPlayingViewModel.snapshot != nil && playingOtherSource == nil ?
        nowPlayingViewModel.elapsedTime(at: date) :
        snapshot.elapsedTime(at: date)
        let progress = progressValue(elapsedTime: elapsedTime, duration: snapshot.duration)
        let displayedProgress = min(max(scrubProgress ?? progress, 0), 1)
        let displayedElapsedTime = snapshot.duration > 0 ?
        TimeInterval(displayedProgress) * snapshot.duration :
        elapsedTime
        let appearance = settings.nowPlayingAppearanceOptions

        return VStack {
            Spacer()

            headerSection(snapshot: snapshot, appearance: appearance)
            
            Spacer()

            PlayerProgressBar(
                progress: displayedProgress,
                displayedElapsedTime: displayedElapsedTime,
                duration: snapshot.duration,
                isInteractive: snapshot.duration > 0 && playingOtherSource == nil,
                tintGradient: {
                    switch appearance.progressTintStyle {
                    case .default:
                        return nil
                    case .artwork:
                        return nowPlayingViewModel.artworkPalette.equalizerGradient
                    case .systemAccent:
                        return LinearGradient(
                            colors: [.accentColor, .accentColor.opacity(0.7)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    }
                }(),
                primaryColor: progressTimeColor(isPrimary: true, appearance: appearance),
                secondaryColor: progressTimeColor(isPrimary: false, appearance: appearance),
                onScrubChanged: { newProgress in
                    scrubProgress = newProgress
                },
                onScrubEnded: { newProgress in
                    nowPlayingViewModel.seek(to: snapshot.duration * TimeInterval(newProgress))
                    scrubProgress = nil
                }
            )

            Spacer()

            controlsSection(snapshot: snapshot, appearance: appearance)

            if let downloadViewModel = DownloadViewModel.current {
                MusicDownloadRow(downloadViewModel: downloadViewModel)
                    .padding(.top, 4)
            }
        }
        .padding(.horizontal, isNotchlessScreen ? 25 : 55)
        .padding(.top, isNotchlessScreen ? 15 : 25)
        .padding(.bottom, 15)
    }

    @ViewBuilder
    private func headerSection(snapshot: NowPlayingSnapshot, appearance: NowPlayingAppearanceOptions) -> some View {
        HStack(spacing: 15) {
            Button(action: {
                openPlaybackSource()
            }) {
                if let playingOtherSource {
                    // Das Cover kennt nur macOS für die aktive App, hier reicht das App-Symbol
                    Group {
                        if let icon = mediaSources.icon(for: playingOtherSource) {
                            Image(nsImage: icon).resizable().interpolation(.high)
                        } else {
                            Image(systemName: "music.note").font(.system(size: 26))
                        }
                    }
                    .frame(width: 60, height: 60)
                    .contentShape(Rectangle())
                } else {
                    ArtworkView(
                        nowPlayingViewModel: nowPlayingViewModel,
                        width: 60,
                        height: 60,
                        cornerRadius: 10,
                        usesFlipAnimation: appearance.usesArtwork3DEffect
                    )
                    .contentShape(Rectangle())
                }
            }
            .buttonStyle(PlaybackSourceButtonStyle())
            .disabled(!nowPlayingViewModel.canOpenPlaybackSource && playingOtherSource == nil)

            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    if mediaSources.sources.count > 1 {
                        sourcePill
                    }

                    Button(action: {
                        openPlaybackSource()
                    }) {
                        VStack(alignment: .leading, spacing: 2) {
                            MarqueeText(
                                .constant(displayTitle(for: snapshot)),
                                font: .system(size: 16, weight: .medium),
                                nsFont: .headline,
                                textColor: .white.opacity(0.8),
                                backgroundColor: .clear,
                                minDuration: 2.0,
                                frameWidth: 170
                            )

                            MarqueeText(
                                .constant(displayArtist(for: snapshot)),
                                font: .system(size: 14),
                                nsFont: .headline,
                                textColor: .white.opacity(0.5),
                                backgroundColor: .clear,
                                minDuration: 3.0,
                                frameWidth: 170
                            )
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(PlaybackSourceButtonStyle())
                    .disabled(!nowPlayingViewModel.canOpenPlaybackSource && playingOtherSource == nil)
                }

                Spacer()

                LightweightNowPlayingEqualizerView(
                    isPlaying: snapshot.isPlaying,
                    colors: [
                        nowPlayingViewModel.artworkPalette.equalizerHighlightColor,
                        nowPlayingViewModel.artworkPalette.equalizerBaseColor
                    ],
                    barHeight: 23,
                    barWidth: 2.7
                )
                .frame(width: 23, height: 18)
            }
        }
    }

    @ViewBuilder
    private func controlsSection(snapshot: NowPlayingSnapshot, appearance: NowPlayingAppearanceOptions) -> some View {
        ZStack {
            HStack(spacing: 25) {
                PlayerControlButton(
                    systemImage: "backward.fill",
                    fontSize: 22,
                    width: 42,
                    height: 42,
                    feedbackStyle: .backward
                ) {
                    nowPlayingViewModel.previousTrack()
                }
                // Zurück/Weiter nimmt macOS nur von der aktiven App an
                .opacity(playingOtherSource == nil ? 1 : 0.3)
                .disabled(playingOtherSource != nil)

                PlayerControlButton(
                    systemImage: snapshot.isPlaying ? "pause.fill" : "play.fill",
                    fontSize: 32,
                    width: 42,
                    height: 42,
                    feedbackStyle: .playPause
                ) {
                    if let playingOtherSource {
                        mediaSources.send(playingOtherSource.isPlaying ? .pause : .play, to: playingOtherSource)
                    } else {
                        nowPlayingViewModel.togglePlayPause()
                    }
                }

                PlayerControlButton(
                    systemImage: "forward.fill",
                    fontSize: 22,
                    width: 42,
                    height: 42,
                    feedbackStyle: .forward
                ) {
                    nowPlayingViewModel.nextTrack()
                }
                .opacity(playingOtherSource == nil ? 1 : 0.3)
                .disabled(playingOtherSource != nil)
            }

            HStack {
                if appearance.showsFavoriteButton {
                    FavoriteTrackButton(
                        nowPlayingViewModel: nowPlayingViewModel,
                        width: 42,
                        height: 42,
                        fontSize: 21
                    )
                }

                Spacer()

                if appearance.showsOutputDeviceButton {
                    AudioOutputRoutePickerButton(
                        nowPlayingViewModel: nowPlayingViewModel,
                        width: 42,
                        height: 42,
                        fontSize: 21
                    )
                }
            }
            .padding(.horizontal, 5)
        }
    }
    
    private func displayTitle(for snapshot: NowPlayingSnapshot) -> String {
        snapshot.title.trimmed.isEmpty ? "Unknown Track" : snapshot.title
    }
    
    private func displayArtist(for snapshot: NowPlayingSnapshot) -> String {
        snapshot.artist.trimmed.isEmpty ? "Unknown Artist" : snapshot.artist
    }
    
    private func displayAlbum(for snapshot: NowPlayingSnapshot) -> String {
        snapshot.album.trimmed.isEmpty ? "Unknown Album" : snapshot.album
    }
    
    private func progressValue(elapsedTime: TimeInterval, duration: TimeInterval) -> CGFloat {
        guard duration > 0 else { return 0 }
        return min(max(CGFloat(elapsedTime / duration), 0), 1)
    }
    
    private func formattedTime(_ time: TimeInterval) -> String {
        guard time.isFinite else { return "--:--" }
        
        let totalSeconds = max(0, Int(time.rounded()))
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        
        return String(format: "%02d:%02d", minutes, seconds)
    }

    private func progressTimeColor(isPrimary: Bool, appearance: NowPlayingAppearanceOptions) -> Color {
        switch appearance.progressTintStyle {
        case .default:
            return .white.opacity(0.4)
        case .artwork:
            let nsColor = isPrimary ?
            nowPlayingViewModel.artworkPalette.equalizerHighlightColor :
            nowPlayingViewModel.artworkPalette.equalizerBaseColor
            return Color(nsColor: nsColor)
        case .systemAccent:
            return isPrimary ? .accentColor : .accentColor.opacity(0.7)
        }
    }
    
    private func playbackStatusColor(for snapshot: NowPlayingSnapshot) -> Color {
        if nowPlayingViewModel.snapshot == nil {
            return .white.opacity(0.48)
        }
        
        return snapshot.isPlaying ?
        Color(red: 0.97, green: 0.73, blue: 0.32) :
            .white.opacity(0.48)
    }

    private func progressTick(for snapshot: NowPlayingSnapshot) -> TimeInterval {
        snapshot.isPlaying ? 1.0 : 30.0
    }

    private func openPlaybackSource() {
        if let playingOtherSource {
            mediaSources.activate(playingOtherSource)
            return
        }
        guard nowPlayingViewModel.canOpenPlaybackSource else { return }
        nowPlayingViewModel.openPlaybackSource()
        if !applicationSettings.isCloseAtFocusLiveActivityEnabled {
            onOpenPlaybackSource()
        }
    }
}
