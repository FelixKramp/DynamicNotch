//
//  IdleNotchContent.swift
//  DynamicNotch
//
//  Created by Евгений Петрукович on 3/29/26.
//

import SwiftUI

/// Idle resting activity representing the Notch / Dynamic Island when no active user Live Activities or alerts are present.
///
/// Ensures the notch maintains active presentation semantics without consuming background system resources.
struct IdleNotchContent: NotchContentProtocol {
    let id: String = NotchContentRegistry.Idle.idle.id
    var stackID: String { id }
    var priority: Int { NotchContentRegistry.Idle.idle.priority }
    var strokeColor: Color { .clear }

    var isExpandable: Bool { false }
    var expandsOnTap: Bool { false }
    var isRestorable: Bool { false }
    var usesContentResizeEffect: Bool { false }
    var allowsPressScaleEffect: Bool { true }
    var allowsCompactPressScaleEffect: Bool { true }

    var widgetURL: (@MainActor () -> Void)? { nil }
    var windowLink: (@MainActor () -> Void)? { nil }

    @MainActor
    func compactView() -> AnyView {
        AnyView(Color.clear)
    }

    func compactSize(baseWidth: CGFloat, baseHeight: CGFloat) -> CGSize {
        CGSize(width: baseWidth, height: baseHeight)
    }

    func compactCornerRadius(baseRadius: CGFloat) -> (top: CGFloat, bottom: CGFloat) {
        (top: baseRadius - 4, bottom: baseRadius)
    }

    @MainActor
    func expandedView() -> AnyView {
        compactView()
    }

    func expandedSize(baseWidth: CGFloat, baseHeight: CGFloat) -> CGSize {
        CGSize(width: baseWidth, height: baseHeight)
    }

    func expandedCornerRadius(baseRadius: CGFloat) -> (top: CGFloat, bottom: CGFloat) {
        compactCornerRadius(baseRadius: baseRadius)
    }

    func dynamicIslandSize(baseWidth: CGFloat, baseHeight: CGFloat) -> CGSize {
        CGSize(width: baseWidth, height: baseHeight)
    }

    func dynamicIslandCornerRadius(baseHeight: CGFloat) -> CGFloat {
        baseHeight * 0.5
    }

    func expandedDynamicIslandSize(baseWidth: CGFloat, baseHeight: CGFloat) -> CGSize {
        CGSize(width: baseWidth, height: baseHeight)
    }

    func expandedDynamicIslandCornerRadius(baseHeight: CGFloat) -> CGFloat {
        baseHeight * 0.5
    }
}
