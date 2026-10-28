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
        VStack(alignment: .leading, spacing: 6) {
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
                Spacer(minLength: 0)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    rows
                }
            }
        }
        .padding(.horizontal, isNotchlessScreen ? 18 : 40)
        .padding(.top, isNotchlessScreen ? 10 : 16)
        .padding(.bottom, 10)
    }

    private var rows: some View {
        VStack(spacing: 6) {
            ForEach(mediaSources.sources) { source in
                MediaSourceRow(
                    mediaSources: mediaSources,
                    source: source,
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
                        .font(.system(size: 14, weight: .semibold))
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

private struct MediaSourceRow: View {
    @ObservedObject var mediaSources: MediaSourcesViewModel
    let source: MediaSource
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
                                .font(.system(size: 14, weight: .semibold))
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
                            .font(.system(size: 12))
                            .foregroundStyle(.white.opacity(0.55))
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }

                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            controlButton(systemImage: source.isPlaying ? "pause.fill" : "play.fill", size: 16) {
                mediaSources.send(source.isPlaying ? .pause : .play, to: source)
            }

            // Weiter geht nur bei der aktiven App, macOS leitet es sonst falsch weiter
            controlButton(systemImage: "forward.fill", size: 13) {
                mediaSources.send(.nextTrack, to: source)
            }
            .opacity(source.isNowPlaying ? 1 : 0.25)
            .disabled(!source.isNowPlaying)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.white.opacity(isCurrent ? 0.14 : 0.05))
        )
        .overlay(
            // Die aktive Quelle bekommt einen Rahmen, damit man sie sofort sieht
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(.white.opacity(isCurrent ? 0.35 : 0), lineWidth: 1)
        )
    }

    @ViewBuilder
    private var iconView: some View {
        if let icon = mediaSources.icon(for: source) {
            Image(nsImage: icon)
                .resizable()
                .interpolation(.high)
                .frame(width: 30, height: 30)
        } else {
            Image(systemName: "music.note")
                .font(.system(size: 16))
                .frame(width: 30, height: 30)
                .foregroundStyle(.white.opacity(0.7))
        }
    }

    private func controlButton(systemImage: String, size: CGFloat, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(.white.opacity(0.9))
                .frame(width: 32, height: 32)
                .background(Circle().fill(.white.opacity(0.12)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
    }
}
