//
//  MusicDownloadViews.swift
//  DynamicNotch
//
//  Läuft Musik, verdrängt sie die Download-Anzeige (Priorität 6 gegen 3).
//  Damit der Fortschritt trotzdem sichtbar bleibt, zeigt der Player ihn mit an:
//  klein als Ring neben dem Equalizer, groß als Zeile unter den Tasten.
//

import SwiftUI

extension DownloadViewModel {
    /// Läuft gerade ein Download? Für die Größen der Musik-Anzeigen.
    static var isDownloading: Bool {
        current?.hasActiveDownloads == true
    }
}

/// Ring für die kleine Notch neben dem Equalizer
struct MusicDownloadBadge: View {
    @ObservedObject var downloadViewModel: DownloadViewModel

    var body: some View {
        if let download = downloadViewModel.primaryDownload {
            DownloadProgressIndicatorView(
                progress: download.progress,
                indicatorStyle: .circle,
                barWidth: 34,
                barHeight: 4,
                circleSize: 16,
                circleLineWidth: 2.5,
                percentFontSize: 12
            )
            .transition(.blurAndFade.combined(with: .scale(scale: 0.6)))
        }
    }
}

/// Zeile im aufgeklappten Player: Datei, Fortschrittsbalken, Prozent
struct MusicDownloadRow: View {
    @ObservedObject var downloadViewModel: DownloadViewModel

    static let height: CGFloat = 30

    var body: some View {
        if let download = downloadViewModel.primaryDownload {
            Button {
                downloadViewModel.openPrimaryDownloadFolder()
            } label: {
                HStack(spacing: 8) {
                    DownloadFileThumbnailView(url: download.url, size: 18)

                    Text(download.displayName)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.75))
                        .lineLimit(1)
                        .truncationMode(.middle)

                    if downloadViewModel.additionalDownloadCount > 0 {
                        Text("+\(downloadViewModel.additionalDownloadCount)")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.white.opacity(0.4))
                    }

                    Spacer(minLength: 8)

                    progressBar(download.progress)

                    Text("\(Int((min(max(download.progress, 0), 1) * 100).rounded())) %")
                        .font(.system(size: 12, weight: .semibold).monospacedDigit())
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 40, alignment: .trailing)
                }
                .padding(.horizontal, 10)
                .frame(height: 26)
                .background(Capsule().fill(.white.opacity(0.07)))
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .help("Download-Ordner öffnen")
            .transition(.blurAndFade.combined(with: .opacity))
        }
    }

    private func progressBar(_ progress: Double) -> some View {
        Capsule()
            .fill(.white.opacity(0.12))
            .frame(width: 70, height: 4)
            .overlay(alignment: .leading) {
                Capsule()
                    .fill(Color.accentColor)
                    .frame(width: 70 * max(0.04, min(CGFloat(progress), 1)), height: 4)
            }
            .animation(.easeOut(duration: 0.3), value: progress)
    }
}
