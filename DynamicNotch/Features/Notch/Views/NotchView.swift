import SwiftUI
import Combine
internal import AppKit
import UniformTypeIdentifiers

struct NotchView: View {
    let notchEventCoordinator: NotchEventCoordinator
    
    @ObservedObject var notchViewModel: NotchViewModel
    @ObservedObject var airDropViewModel: AirDropNotchViewModel
    @ObservedObject var airDropController: NotchAirDropController
    @ObservedObject var settingsViewModel: SettingsViewModel
    
    @Environment(\.openWindow) private var openWindow
    
    var body: some View {
        NotchInteractiveBodyView(
            notchViewModel: notchViewModel,
            settingsViewModel: settingsViewModel
        )
        .environment(\.notchScale, notchViewModel.notchModel.scale)
        .overlay {
            NotchDragAndDropDestinationOverlay(
                airDropViewModel: airDropViewModel,
                airDropController: airDropController,
                settingsViewModel: settingsViewModel
            )
        }
        .onChange(of: notchViewModel.displayedContent?.id) {
            notchViewModel.handleStrokeVisibility()
        }
        .onChange(of: settingsViewModel.application.notchWidth) { _, _ in
            notchViewModel.updateDimensions()
        }
        .onChange(of: settingsViewModel.application.notchHeight) { _, _ in
            notchViewModel.updateDimensions()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}
