//
//  LocalTimerSetupNotchContent.swift
//  DynamicNotch
//

import SwiftUI

struct LocalTimerSetupNotchContent: NotchContentProtocol, DynamicIslandCustomizable {
    let id = NotchContentRegistry.Media.localTimerSetup.id
    let localTimerViewModel: LocalTimerViewModel
    var onClose: (() -> Void)? = nil
    var priority: Int { NotchContentPriority.localTimerSetup }
    var allowsCompactPressScaleEffect: Bool = false

    var strokeColor: Color {
        .orange.opacity(0.3)
    }
    
    func cornerRadius(baseRadius: CGFloat) -> (top: CGFloat, bottom: CGFloat) {
        (top: 24, bottom: 42)
    }

    func size(baseWidth: CGFloat, baseHeight: CGFloat) -> CGSize {
        .init(width: baseWidth + 160, height: baseHeight + 130)
    }

    func dynamicIslandSize(baseWidth: CGFloat, baseHeight: CGFloat) -> CGSize {
        .init(width: baseWidth + 220, height: baseHeight + 130)
    }
    
    func dynamicIslandCornerRadius(baseHeight: CGFloat) -> CGFloat {
        baseHeight * 0.25
    }

    @MainActor
    func makeView() -> AnyView {
        AnyView(LocalTimerSetupNotchView(localTimerViewModel: localTimerViewModel, onClose: onClose))
    }
}
