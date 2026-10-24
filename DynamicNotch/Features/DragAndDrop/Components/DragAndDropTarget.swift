import SwiftUI

enum DragAndDropTarget: String, Hashable, CaseIterable {
    case airDrop
    case tray

    var title: LocalizedStringKey {
        switch self {
        case .airDrop:
            return "AirDrop"
            
        case .tray:
            return "Tray"
        }
    }

    var color: Color {
        switch self {
        case .airDrop:
            return .blue

        case .tray:
            return .white
        }
    }

    var activityStrokeColor: Color {
        color.opacity(0.3)
    }

    var acceptsDrop: Bool {
        switch self {
        case .airDrop, .tray:
            return true
        }
    }

    @ViewBuilder
    func titleIcon(locale: Locale? = nil) -> some View {
        switch self {
        case .airDrop:
            Text(locale?.dn("notch.dragDrop.airDrop", fallback: "AirDrop") ?? L10n.notch("notch.dragDrop.airDrop", fallback: "AirDrop"))
                .font(.system(size: 12))
                .foregroundStyle(.white)

        case .tray:
            Text(locale?.dn("notch.dragDrop.tray", fallback: "Tray") ?? L10n.notch("notch.dragDrop.tray", fallback: "Tray"))
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
        }
    }
}
