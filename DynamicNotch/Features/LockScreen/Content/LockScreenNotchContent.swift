import SwiftUI

enum LockScreenEvent: Equatable {
    case started
    case stopped
}

struct LockScreenNotchContent: NotchContentProtocol, DynamicIslandCustomizable {
    let id = NotchContentRegistry.LockScreen.activity.id
    let lockScreenManager: LockScreenManager

    var priority: Int { NotchContentRegistry.LockScreen.activity.priority }

    func compactSize(baseWidth: CGFloat, baseHeight: CGFloat) -> CGSize {
        .init(width: baseWidth + 55, height: baseHeight)
    }
    
    func dynamicIslandSize(baseWidth: CGFloat, baseHeight: CGFloat) -> CGSize {
        .init(width: baseWidth + 50, height: baseHeight)
    }

    @MainActor
    func compactView() -> AnyView {
        AnyView(LockScreenNotchView(lockScreenManager: lockScreenManager))
    }
}
