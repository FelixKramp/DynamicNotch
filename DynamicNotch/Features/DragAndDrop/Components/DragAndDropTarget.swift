import SwiftUI

enum DragAndDropTarget: String, Hashable, CaseIterable {
    case airDrop
    case tray
    /// Blip: Dateien auch an Android-Geräte schicken
    case blip

    var title: LocalizedStringKey {
        switch self {
        case .airDrop:
            return "AirDrop"
            
        case .tray:
            return "Tray"

        case .blip:
            return "Blip"
        }
    }

    var color: Color {
        switch self {
        case .airDrop:
            return .blue

        case .tray:
            return .white

        case .blip:
            return Color(red: 0.36, green: 0.84, blue: 0.62)
        }
    }

    var activityStrokeColor: Color {
        color.opacity(0.3)
    }

    var acceptsDrop: Bool {
        switch self {
        case .airDrop, .tray, .blip:
            return true
        }
    }

    @ViewBuilder
    func titleIcon() -> some View {
        switch self {
        case .airDrop:
            Text(verbatim: "AirDrop")
                .font(.system(size: 12))
                .foregroundStyle(.white)

        case .tray:
            Text(verbatim: "Tray")
                .font(.system(size: 12))
                .foregroundStyle(color)

        case .blip:
            Text(verbatim: "Blip")
                .font(.system(size: 12))
                .foregroundStyle(color)
        }
    }

    @ViewBuilder
    func icon() -> some View {
        switch self {
        case .airDrop:
            Image("airdrop.white")
                .resizable()
                .renderingMode(.template)
                .foregroundStyle(color)
                .frame(width: 28, height: 28)

        case .tray:
            Image(systemName: "tray.full.fill")
                .font(.system(size: 22))
                .foregroundStyle(color)
                .frame(width: 28, height: 28)

        case .blip:
            if let icon = BlipService.appIcon {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 30, height: 30)
            } else {
                Image(systemName: "paperplane.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(color)
                    .frame(width: 28, height: 28)
            }
        }
    }
}
