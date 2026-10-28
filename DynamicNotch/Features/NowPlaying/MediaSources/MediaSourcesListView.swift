//
//  MediaSourcesListView.swift
//  DynamicNotch
//
//  Liste aller Medienquellen im aufgeklappten Player. Jede Zeile hat eigene
//  Tasten, damit Pause bei YouTube nicht TIDAL trifft.
//

import SwiftUI

struct MediaSourcesListView: View {
    @Environment(\.isNotchlessScreen) private var isNotchlessScreen

    @ObservedObject var mediaSources: MediaSourcesViewModel
    let currentBundleIdentifier: String?
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            header

            if mediaSources.sources.isEmpty {
                Spacer()
                Text("Keine Medienquellen aktiv")
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.5))
                    .frame(maxWidth: .infinity)
                Spacer()
            } else if mediaSources.sources.count <= 3 {
                rows
                    .frame(maxHeight: .infinity, alignment: mediaSources.sources.count == 1 ? .center : .top)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    rows
                }
            }
        }
        .padding(.horizontal, isNotchlessScreen ? 18 : 40)
        // Unterhalb der Kamera-Aussparung (32 pt), sonst ist der Zurück-Pfeil verdeckt
        .padding(.top, isNotchlessScreen ? 10 : 35)
        .padding(.bottom, 8)
    }

    private var rows: some View {
        // Bei ein oder zwei Quellen ist Platz für große Zeilen, ab drei wird es kompakt
        let metrics: MediaSourceRowMetrics = mediaSources.sources.count <= 2 ? .large : .compact
        return VStack(spacing: metrics.spacing) {
            ForEach(mediaSources.sources) { source in
                MediaSourceRow(
                    mediaSources: mediaSources,
                    source: source,
                    metrics: metrics,
                    isCurrent: currentBundleIdentifier.map { $0 == source.bundleIdentifier } ?? source.isNowPlaying
                )
            }
        }
    }

    private var header: some View {
        HStack(spacing: 6) {
            Button(action: onClose) {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 12, weight: .semibold))
                    Text("Quellen")
                        .font(.system(size: 13, weight: .semibold))
                }
                .foregroundStyle(.white.opacity(0.85))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Spacer()

            Text("\(mediaSources.sources.count)")
                .font(.system(size: 12, weight: .medium).monospacedDigit())
                .foregroundStyle(.white.opacity(0.4))
        }
    }
}

private struct MediaSourceRowMetrics {
    let icon: CGFloat
    let title: CGFloat
    let subtitle: CGFloat
    let playButton: CGFloat
    let playSymbol: CGFloat
    let nextButton: CGFloat
    let nextSymbol: CGFloat
    let verticalPadding: CGFloat
    let spacing: CGFloat
    let cornerRadius: CGFloat

    static let large = MediaSourceRowMetrics(
        icon: 38, title: 16, subtitle: 13,
        playButton: 44, playSymbol: 19, nextButton: 36, nextSymbol: 14,
        verticalPadding: 7, spacing: 7, cornerRadius: 15
    )
    static let compact = MediaSourceRowMetrics(
        icon: 26, title: 13, subtitle: 11,
        playButton: 34, playSymbol: 16, nextButton: 28, nextSymbol: 12,
        verticalPadding: 3, spacing: 4, cornerRadius: 12
    )
}

private struct MediaSourceRow: View {
    @ObservedObject var mediaSources: MediaSourcesViewModel
    let source: MediaSource
    let metrics: MediaSourceRowMetrics
    let isCurrent: Bool

    var body: some View {
        HStack(spacing: 10) {
            Button {
                mediaSources.activate(source)
            } label: {
                HStack(spacing: 10) {
                    iconView

                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: 5) {
                            Text(source.name)
                                .font(.system(size: metrics.title, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.95))
                                .lineLimit(1)

                            if source.isPlaying {
                                Image(systemName: "waveform")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(.green.opacity(0.85))
                                    .symbolEffect(.variableColor.iterative, options: .repeating)
                            }
                        }

                        Text(source.subtitle.isEmpty ? " " : source.subtitle)
                            .font(.system(size: metrics.subtitle))
                            .foregroundStyle(.white.opacity(0.55))
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }

                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            controlButton(systemImage: source.isPlaying ? "pause.fill" : "play.fill", symbolSize: metrics.playSymbol, diameter: metrics.playButton) {
                mediaSources.send(source.isPlaying ? .pause : .play, to: source)
            }

            // Weiter geht nur bei der aktiven App, macOS leitet es sonst falsch weiter
            controlButton(systemImage: "forward.fill", symbolSize: metrics.nextSymbol, diameter: metrics.nextButton) {
                mediaSources.send(.nextTrack, to: source)
            }
            .opacity(source.isNowPlaying ? 1 : 0.25)
            .disabled(!source.isNowPlaying)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, metrics.verticalPadding)
        .background(
            RoundedRectangle(cornerRadius: metrics.cornerRadius, style: .continuous)
                .fill(.white.opacity(isCurrent ? 0.14 : 0.05))
        )
        .overlay(
            // Die aktive Quelle bekommt einen Rahmen, damit man sie sofort sieht
            RoundedRectangle(cornerRadius: metrics.cornerRadius, style: .continuous)
                .stroke(.white.opacity(isCurrent ? 0.35 : 0), lineWidth: 1)
        )
    }

    @ViewBuilder
    private var iconView: some View {
        if let icon = mediaSources.icon(for: source) {
            Image(nsImage: icon)
                .resizable()
                .interpolation(.high)
                .frame(width: metrics.icon, height: metrics.icon)
        } else {
            Image(systemName: "music.note")
                .font(.system(size: metrics.icon * 0.55))
                .frame(width: metrics.icon, height: metrics.icon)
                .foregroundStyle(.white.opacity(0.7))
        }
    }

    private func controlButton(systemImage: String, symbolSize: CGFloat, diameter: CGFloat, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: symbolSize, weight: .semibold))
                .foregroundStyle(.white.opacity(0.9))
                .contentTransition(.symbolEffect(.replace))
                .frame(width: diameter, height: diameter)
                .background(Circle().fill(.white.opacity(0.12)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
    }
}
