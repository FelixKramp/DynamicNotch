import SwiftUI

enum LockScreenEvent: Equatable {
    case started
    case stopped
}

struct LockScreenNotchContent: NotchContentProtocol, DynamicIslandCustomizable {
    let id = NotchContentRegistry.LockScreen.activity.id
    let lockScreenManager: LockScreenManager
    var faceIDSettings: FaceIDSettingsStore? = nil
    var faceIDService: FaceIDService = .shared

    var priority: Int { NotchContentRegistry.LockScreen.activity.priority }

    private var isCompactFaceIDActive: Bool {
        guard let faceIDSettings, faceIDSettings.presentationStyle == .compact else { return false }
        return faceIDService.state.isActivelyEvaluating || faceIDService.state.isSuccess || lockScreenManager.didUnlockWithFaceID
    }

    func compactSize(baseWidth: CGFloat, baseHeight: CGFloat) -> CGSize {
        if isCompactFaceIDActive {
            return .init(width: baseWidth + 95, height: baseHeight + 10)
        }
        return .init(width: baseWidth + 55, height: baseHeight)
    }
    
    func dynamicIslandSize(baseWidth: CGFloat, baseHeight: CGFloat) -> CGSize {
        if isCompactFaceIDActive {
            return .init(width: baseWidth + 95, height: baseHeight + 10)
        }
        return .init(width: baseWidth + 55, height: baseHeight)
    }

    func compactCornerRadius(baseRadius: CGFloat) -> (top: CGFloat, bottom: CGFloat) {
        if isCompactFaceIDActive {
            return (top: max(4, baseRadius - 2), bottom: baseRadius + 3)
        }
        return (top: baseRadius - 4, bottom: baseRadius)
    }

    func dynamicIslandCornerRadius(baseHeight: CGFloat) -> CGFloat {
        if isCompactFaceIDActive {
            return (baseHeight + 6) * 0.5
        }
        return baseHeight * 0.5
    }

    @MainActor
    func compactView() -> AnyView {
        AnyView(LockScreenNotchView(lockScreenManager: lockScreenManager, faceIDService: faceIDService))
    }
}

