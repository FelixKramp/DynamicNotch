//
//  FaceIDSettingsStore.swift
//  DynamicNotch
//

import Foundation
import Combine

@MainActor
final class FaceIDSettingsStore: SettingsStoreBase {
    @StoredDefault(key: FaceIDSettings.enabledKey, defaultValue: true)
    var isFaceIDEnabled: Bool

    @StoredDefault(key: FaceIDSettings.isEnrolledKey, defaultValue: false)
    var isEnrolled: Bool

    @StoredDefault(key: FaceIDSettings.enrolledDateKey, defaultValue: "")
    var enrolledDateString: String

    @StoredDefault(key: FaceIDSettings.requireOpenEyesKey, defaultValue: true)
    var requireOpenEyes: Bool

    @StoredDefault(key: FaceIDSettings.livenessCheckKey, defaultValue: true)
    var livenessCheck: Bool

    @StoredDefault(key: FaceIDSettings.unlockOnWakeKey, defaultValue: true)
    var unlockOnWake: Bool

    @StoredDefault(key: FaceIDSettings.lowLightAssistKey, defaultValue: true)
    var isLowLightAssistEnabled: Bool

    @StoredDefault(key: FaceIDSettings.showLockScreenButtonKey, defaultValue: true)
    var showLockScreenButton: Bool

    func reset() {
        isFaceIDEnabled = defaultBool(for: FaceIDSettings.enabledKey)
        isEnrolled = defaultBool(for: FaceIDSettings.isEnrolledKey)
        enrolledDateString = defaultString(for: FaceIDSettings.enrolledDateKey)
        requireOpenEyes = defaultBool(for: FaceIDSettings.requireOpenEyesKey)
        livenessCheck = defaultBool(for: FaceIDSettings.livenessCheckKey)
        unlockOnWake = defaultBool(for: FaceIDSettings.unlockOnWakeKey)
        isLowLightAssistEnabled = defaultBool(for: FaceIDSettings.lowLightAssistKey)
        showLockScreenButton = defaultBool(for: FaceIDSettings.showLockScreenButtonKey)
    }

    func enrollFace() {
        isEnrolled = true
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        enrolledDateString = formatter.string(from: Date())
    }

    func resetFace() {
        isEnrolled = false
        enrolledDateString = ""
    }
}
