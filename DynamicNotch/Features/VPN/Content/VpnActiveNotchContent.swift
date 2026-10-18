//
//  VpnActiveNotchContent.swift
//  DynamicNotch
//

import SwiftUI

struct VpnActiveNotchContent: NotchContentProtocol, DynamicIslandCustomizable {
    let id = NotchContentRegistry.Vpn.vpn.id
    let vpnViewModel: VpnViewModel
    let notchViewModel: NotchViewModel

    var priority: Int { NotchContentRegistry.Vpn.vpn.priority }
    var isExpandable: Bool { true }

    func size(baseWidth: CGFloat, baseHeight: CGFloat) -> CGSize {
        .init(width: baseWidth + 105, height: baseHeight)
    }

    func expandedSize(baseWidth: CGFloat, baseHeight: CGFloat) -> CGSize {
        .init(width: baseWidth + 160, height: baseHeight + 65)
    }
    
    func expandedDynamicIslandSize(baseWidth: CGFloat, baseHeight: CGFloat) -> CGSize {
        .init(width: baseWidth + 220, height: baseHeight + 65)
    }

    func expandedCornerRadius(baseRadius: CGFloat) -> (top: CGFloat, bottom: CGFloat) {
        (top: 20, bottom: 38)
    }
    
    func expandedDynamicIslandCornerRadius(baseHeight: CGFloat) -> CGFloat {
        baseHeight * 0.45
    }

    var windowLink: (@MainActor () -> Void)? {
        return {
            SettingsWindowController.shared.showWindow(selecting: .network)
        }
    }

    @MainActor
    func makeView() -> AnyView {
        AnyView(
            VpnActiveNotchView(vpnViewModel: vpnViewModel)
        )
    }

    @MainActor
    func makeExpandedView() -> AnyView {
        AnyView(
            VpnExpandedNotchView(
                notchViewModel: notchViewModel,
                viewModel: vpnViewModel
            )
        )
    }
}
