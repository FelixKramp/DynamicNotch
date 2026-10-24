//
//  NotchStrokeOpacityNotchContent.swift
//  DynamicNotch
//

import SwiftUI

struct NotchStrokeOpacityNotchContent: NotchContentProtocol, DynamicIslandCustomizable {
    let id = NotchContentRegistry.NotchSize.strokeOpacity.id
    let settingsViewModel: SettingsViewModel

    var priority: Int { NotchContentRegistry.NotchSize.strokeOpacity.priority }

    func compactSize(baseWidth: CGFloat, baseHeight: CGFloat) -> CGSize {
        return .init(width: baseWidth + 100, height: baseHeight)
    }

    @MainActor
    func compactView() -> AnyView {
        AnyView(NotchStrokeOpacityNotchView(settingsViewModel: settingsViewModel))
    }
}
