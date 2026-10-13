//
//  FaceIDSettings.swift
//  DynamicNotch
//

import Foundation

enum FaceIDSettings {
    static let enabledKey = "settings.faceid.enabled"
    static let isEnrolledKey = "settings.faceid.isEnrolled"
    static let enrolledDateKey = "settings.faceid.enrolledDate"
    static let requireAttentionKey = "settings.faceid.requireAttention"
    static let requireOpenEyesKey = "settings.faceid.requireOpenEyes"
    static let livenessCheckKey = "settings.faceid.livenessCheck"
    static let unlockOnWakeKey = "settings.faceid.unlockOnWake"
    static let lowLightAssistKey = "settings.faceid.lowLightAssist"
    static let showLockScreenButtonKey = "settings.faceid.showLockScreenButton"
}
