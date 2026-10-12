//
//  FaceIDNotchContent.swift
//  DynamicNotch
//

import SwiftUI

struct FaceIDNotchContent: NotchContentProtocol, DynamicIslandCustomizable {
    let id: String = NotchContentRegistry.FaceID.scanning.id
    var priority: Int { NotchContentPriority.faceID }

    let service: FaceIDService

    var strokeColor: Color {
        if service.state.isSuccess {
            return .green.opacity(0.3)
        } else if service.state.isFailed {
            return .green.opacity(0.3)
        } else {
            return .white.opacity(0.2)
        }
    }

    func size(baseWidth: CGFloat, baseHeight: CGFloat) -> CGSize {
        CGSize(width: baseWidth + 40, height: baseHeight + 125)
    }

    func dynamicIslandSize(baseWidth: CGFloat, baseHeight: CGFloat) -> CGSize {
        CGSize(width: baseWidth + 40, height: baseHeight + 120)
    }

    func cornerRadius(baseRadius: CGFloat) -> (top: CGFloat, bottom: CGFloat) {
        (top: 24, bottom: 44)
    }

    func dynamicIslandCornerRadius(baseHeight: CGFloat) -> CGFloat {
        baseHeight * 0.25
    }

    @MainActor
    func makeView() -> AnyView {
        AnyView(
            FaceIDNotchView(service: service)
        )
    }
}
