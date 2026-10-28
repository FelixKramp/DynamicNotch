//
//  ClaudeActivityViews.swift
//  DynamicNotch
//
//  Kompakt- und Detailansicht für den Claude-Fortschritt. Aufbau angelehnt an
//  savvy-progress: Krabbe, Titel, Phase, erledigte von geplanten Schritten,
//  eine Krabbe pro Subagent. Läuft Musik, teilt sich die Notch: links Claude,
//  rechts die Musik.
//

import SwiftUI

enum ClaudeStyle {
    static let accent = Color(red: 0.85, green: 0.47, blue: 0.34)

    static func toolIcon(for tool: String?) -> String {
        switch tool {
        case "Terminal": "terminal"
        case "Liest": "doc.text"
        case "Bearbeitet", "Schreibt": "pencil"
        case "Sucht": "magnifyingglass"
        case "Websuche", "Lädt Seite": "globe"
        case "Subagent": "person.2"
        case "Wartet auf dich": "hand.raised"
        case "Denkt nach": "brain"
        case "Fasst zusammen": "text.alignleft"
        case "Fertig": "checkmark"
        default: "hammer"
        }
    }

    static func elapsedText(since start: Date?, now: Date) -> String {
        guard let start else { return "" }
        let seconds = max(0, Int(now.timeIntervalSince(start)))
        return seconds >= 3600
            ? String(format: "%d:%02d:%02d", seconds / 3600, seconds / 60 % 60, seconds % 60)
            : String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

struct ClaudeStepBar: View {
    let session: ClaudeSession
    var height: CGFloat = 5

    var body: some View {
        if session.hasPlan {
            HStack(spacing: 3) {
                ForEach(Array(session.tasks.enumerated()), id: \.offset) { _, task in
                    Capsule()
                        .fill(color(for: task))
                        .frame(height: height)
                        .overlay {
                            if task.isActive {
                                PulsingCapsule(height: height)
                            }
                        }
                }
            }
        } else {
            // Kein Plan gemeldet: unbestimmter Balken, solange gearbeitet wird
            GeometryReader { proxy in
                TimelineView(.animation) { context in
                    let phase = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.6) / 1.6
                    ZStack(alignment: .leading) {
                        Capsule().fill(.white.opacity(0.12))
                        Capsule()
                            .fill(ClaudeStyle.accent)
                            .frame(width: proxy.size.width * 0.3)
                            .offset(x: (proxy.size.width * 1.3) * phase - proxy.size.width * 0.3)
                    }
                    .clipShape(Capsule())
                }
            }
            .frame(height: height)
        }
    }

    private func color(for task: ClaudeTask) -> Color {
        if task.isCompleted { return ClaudeStyle.accent }
        if task.isActive { return ClaudeStyle.accent.opacity(0.45) }
        return .white.opacity(0.14)
    }
}

private struct PulsingCapsule: View {
    let height: CGFloat
    @State private var isBright = false

    var body: some View {
        Capsule()
            .fill(ClaudeStyle.accent)
            .opacity(isBright ? 0.95 : 0.25)
            .frame(height: height)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                    isBright = true
                }
            }
    }
}

/// Die Krabben der Subagenten, nebeneinander; ab fünf nur noch eine Zahl
struct ClaudeCrewView: View {
    let agents: [ClaudeAgent]
    var height: CGFloat = 15

    var body: some View {
        HStack(spacing: 2) {
            ForEach(Array(agents.prefix(4).enumerated()), id: \.offset) { index, agent in
                ClaudeCrabView(
                    costume: .forSubagent(type: agent.type, index: index),
                    isWalking: true,
                    height: height
                )
                .help(agent.description)
            }
            if agents.count > 4 {
                Text("+\(agents.count - 4)")
                    .font(.system(size: 10, weight: .semibold).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.6))
            }
        }
    }
}

// MARK: - Kompakt (neben der Notch)

struct ClaudeNotchView: View {
    @Environment(\.notchScale) private var scale
    @Environment(\.isNotchlessScreen) private var isNotchlessScreen

    @ObservedObject var viewModel: ClaudeActivityViewModel
    @ObservedObject var nowPlayingViewModel: NowPlayingViewModel

    var body: some View {
        HStack(spacing: 5) {
            ClaudeCrabView(
                isWalking: session?.isWorking ?? false,
                height: isNotchlessScreen ? 15 : 18
            )

            if showsMusic {
                // Musik läuft: Claude-Stand wandert nach links neben die Krabbe
                claudeStatus
            }

            Spacer()

            if showsMusic {
                musicStatus
            } else {
                claudeStatus
            }
        }
        .padding(.leading, isNotchlessScreen ? 6.scaled(by: scale) : 11.scaled(by: scale))
        .padding(.trailing, isNotchlessScreen ? 6.scaled(by: scale) : 13.scaled(by: scale))
    }

    private var session: ClaudeSession? { viewModel.primarySession }
    private var showsMusic: Bool { nowPlayingViewModel.snapshot?.isPlaying == true }

    @ViewBuilder
    private var claudeStatus: some View {
        if let session {
            if session.isWaiting {
                Image(systemName: "hand.raised.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(ClaudeStyle.accent)
                    .symbolEffect(.pulse, options: .repeating)
            } else if session.hasPlan {
                Text("\(session.completedCount)/\(session.tasks.count)")
                    .font(.system(size: 12, weight: .semibold).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.9))
            } else {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text(ClaudeStyle.elapsedText(since: session.startedAt, now: context.date))
                        .font(.system(size: 12, weight: .medium).monospacedDigit())
                        .foregroundStyle(.white.opacity(0.8))
                }
            }
        }
    }

    private var musicStatus: some View {
        HStack(spacing: 5) {
            ArtworkView(
                nowPlayingViewModel: nowPlayingViewModel,
                width: 18,
                height: 18,
                cornerRadius: 4,
                usesFlipAnimation: false
            )
            LightweightNowPlayingEqualizerView(
                isPlaying: true,
                colors: [
                    nowPlayingViewModel.artworkPalette.equalizerHighlightColor,
                    nowPlayingViewModel.artworkPalette.equalizerBaseColor
                ],
                barHeight: 14,
                barWidth: 2
            )
            .frame(width: 14, height: 12)
        }
    }
}

// MARK: - Aufgeklappt

struct ClaudeExpandedNotchView: View {
    @Environment(\.isNotchlessScreen) private var isNotchlessScreen

    @ObservedObject var viewModel: ClaudeActivityViewModel
    @ObservedObject var nowPlayingViewModel: NowPlayingViewModel

    var body: some View {
        VStack(spacing: 10) {
            if let session = viewModel.primarySession {
                content(for: session)
            } else {
                Text("Claude ist fertig")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white.opacity(0.7))
            }

            if let snapshot = nowPlayingViewModel.snapshot {
                Divider().overlay(.white.opacity(0.12))
                miniPlayer(snapshot: snapshot)
            }
        }
        .padding(.horizontal, isNotchlessScreen ? 22 : 40)
        .padding(.top, isNotchlessScreen ? 12 : 20)
        .padding(.bottom, 12)
    }

    private func content(for session: ClaudeSession) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                ClaudeCrabView(isWalking: session.isWorking, height: 22)

                Text(session.project ?? "Claude")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.9))
                    .lineLimit(1)

                Spacer(minLength: 4)

                if !session.crew.isEmpty {
                    ClaudeCrewView(agents: session.crew)
                }

                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text(ClaudeStyle.elapsedText(since: session.startedAt, now: context.date))
                        .font(.system(size: 12, weight: .medium).monospacedDigit())
                        .foregroundStyle(.white.opacity(0.45))
                }
            }

            ClaudeStepBar(session: session)

            HStack(spacing: 6) {
                if session.hasPlan {
                    Text("Schritt \(session.currentStepNumber)/\(session.tasks.count)")
                        .font(.system(size: 11, weight: .semibold).monospacedDigit())
                        .foregroundStyle(ClaudeStyle.accent)
                }

                Text(session.isWaiting ? "Wartet auf dich" : session.headline)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(session.isWaiting ? ClaudeStyle.accent : .white.opacity(0.85))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            HStack(spacing: 6) {
                Image(systemName: ClaudeStyle.toolIcon(for: session.currentTool))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.55))
                    .frame(width: 14)

                Text(session.currentTool ?? "")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.65))

                if let detail = session.currentDetail, !detail.isEmpty {
                    Text(detail)
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.4))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer(minLength: 0)

                if viewModel.additionalSessionCount > 0 {
                    Text("+\(viewModel.additionalSessionCount) Sitzung")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.4))
                }
            }
        }
    }

    /// Musik bleibt bedienbar, während Claude die Notch belegt
    private func miniPlayer(snapshot: NowPlayingSnapshot) -> some View {
        HStack(spacing: 10) {
            ArtworkView(
                nowPlayingViewModel: nowPlayingViewModel,
                width: 28,
                height: 28,
                cornerRadius: 6,
                usesFlipAnimation: false
            )

            VStack(alignment: .leading, spacing: 0) {
                Text(snapshot.title.isEmpty ? "Unbekannter Titel" : snapshot.title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.85))
                    .lineLimit(1)
                Text(snapshot.artist)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.5))
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            miniButton("backward.fill", size: 12) { nowPlayingViewModel.previousTrack() }
            miniButton(snapshot.isPlaying ? "pause.fill" : "play.fill", size: 15) { nowPlayingViewModel.togglePlayPause() }
            miniButton("forward.fill", size: 12) { nowPlayingViewModel.nextTrack() }
        }
    }

    private func miniButton(_ systemImage: String, size: CGFloat, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(.white.opacity(0.9))
                .frame(width: 26, height: 26)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Kurze Fertig-Meldung

struct ClaudeFinishedNotchView: View {
    @Environment(\.notchScale) private var scale
    let project: String

    var body: some View {
        HStack {
            ClaudeCrabView(isWalking: false, height: 18)

            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.green.opacity(0.85))
            Text("Fertig")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white.opacity(0.9))
        }
        .padding(.leading, 11.scaled(by: scale))
        .padding(.trailing, 14.scaled(by: scale))
    }
}
