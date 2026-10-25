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

    @StoredDefault(key: FaceIDSettings.requireAttentionKey, defaultValue: true)
    var requireAttention: Bool {
        didSet {
            requireOpenEyes = requireAttention
            livenessCheck = requireAttention
        }
    }

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

    @StoredDefault(key: FaceIDSettings.presentationStyleKey, defaultValue: FaceIDPresentationStyle.expanded.rawValue)
    private var rawPresentationStyle: String

    var presentationStyle: FaceIDPresentationStyle {
        get { FaceIDPresentationStyle(rawValue: rawPresentationStyle) ?? .expanded }
        set { rawPresentationStyle = newValue.rawValue }
    }

    func reset() {
        isFaceIDEnabled = defaultBool(for: FaceIDSettings.enabledKey)
        isEnrolled = defaultBool(for: FaceIDSettings.isEnrolledKey)
        enrolledDateString = defaultString(for: FaceIDSettings.enrolledDateKey)
        requireAttention = defaultBool(for: FaceIDSettings.requireAttentionKey)
        requireOpenEyes = defaultBool(for: FaceIDSettings.requireOpenEyesKey)
        livenessCheck = defaultBool(for: FaceIDSettings.livenessCheckKey)
        unlockOnWake = defaultBool(for: FaceIDSettings.unlockOnWakeKey)
        isLowLightAssistEnabled = defaultBool(for: FaceIDSettings.lowLightAssistKey)
        showLockScreenButton = defaultBool(for: FaceIDSettings.showLockScreenButtonKey)
        rawPresentationStyle = FaceIDPresentationStyle.expanded.rawValue
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
