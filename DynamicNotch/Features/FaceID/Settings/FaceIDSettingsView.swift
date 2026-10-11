//
//  FaceIDSettingsView.swift
//  DynamicNotch
//

import SwiftUI

struct FaceIDSettingsView: View {
    @ObservedObject var settings: FaceIDSettingsStore
    @ObservedObject var applicationSettings: ApplicationSettingsStore
    var notchViewModel: NotchViewModel?

    @StateObject private var service = FaceIDService.shared
    @State private var isShowingEnrollmentSheet = false
    @State private var isShowingResetConfirmation = false
    @State private var isShowingSecuritySheet = false
    @State private var hasStoredPassword = FaceIDKeychainService.hasPassword
    @State private var passwordInput = ""
    @State private var isVerifyingPassword = false
    @State private var passwordErrorMessage: String? = nil

    var body: some View {
        SettingsPageScrollView {
            faceIDGeneralCard
            faceEnrollmentCard
            securityOptionsCard
        }
        .sheet(isPresented: $isShowingEnrollmentSheet) {
            FaceIDEnrollmentSheetView(settings: settings, service: service)
        }
        .sheet(isPresented: $isShowingSecuritySheet) {
            securityVerificationSheet
        }
        .confirmationDialog(
            "settings.faceid.reset.title",
            isPresented: $isShowingResetConfirmation,
            titleVisibility: .visible
        ) {
            Button("settings.faceid.reset.delete", role: .destructive) {
                settings.resetFace()
                FaceIDKeychainService.deletePassword()
                hasStoredPassword = false
            }
            Button("settings.faceid.security.cancel", role: .cancel) {}
        } message: {
            Text("settings.faceid.reset.message")
        }
        .onAppear {
            hasStoredPassword = FaceIDKeychainService.hasPassword
        }
    }

    private var faceIDGeneralCard: some View {
        SettingsCard(title: "settings.faceid.card.general") {
            SettingsToggleRow(
                title: "settings.faceid.toggle.enabled.title",
                description: "settings.faceid.toggle.enabled.desc",
                systemImage: "faceid",
                color: .green,
                isOn: $settings.isFaceIDEnabled,
                accessibilityIdentifier: "settings.faceid.enabled"
            )
            
            Divider()
                .opacity(0.6)
                .padding(.leading, 43)
            
            SettingsToggleRow(
                title: "settings.faceid.toggle.lockScreenButton.title",
                description: "settings.faceid.toggle.lockScreenButton.desc",
                systemImage: "ellipsis",
                color: .blue,
                isOn: $settings.showLockScreenButton,
                accessibilityIdentifier: "settings.faceid.showLockScreenButton"
            )
        }
    }

    private var faceEnrollmentCard: some View {
        SettingsCard(title: "settings.faceid.card.profile") {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(settings.isEnrolled ? Color.green.opacity(0.15) : Color.blue.opacity(0.15))
                        .frame(width: 44, height: 44)

                    Image(systemName: settings.isEnrolled ? "checkmark.seal.fill" : "person.crop.circle.badge.plus")
                        .font(.system(size: 22))
                        .foregroundStyle(settings.isEnrolled ? .green : .blue)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(settings.isEnrolled ? "settings.faceid.status.enrolled" : "settings.faceid.status.notEnrolled")
                        .font(.system(size: 13, weight: .semibold))

                    if settings.isEnrolled && !settings.enrolledDateString.isEmpty {
                        Text(applicationSettings.appLanguage.locale.dnFormat(
                            "settings.faceid.status.enrolled.date",
                            fallback: "Настроено: %@ • Защищено связкой ключей",
                            settings.enrolledDateString
                        ))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    } else if settings.isEnrolled {
                        Text("settings.faceid.status.enrolled.active")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    } else {
                        Text("settings.faceid.status.notEnrolled.desc")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                if settings.isEnrolled {
                    Menu {
                        Button("settings.faceid.action.reconfigure") {
                            requestSecurityVerification()
                        }
                        Button("settings.faceid.action.delete", role: .destructive) {
                            isShowingResetConfirmation = true
                        }
                    } label: {
                        Text("settings.faceid.action.enrolledMenu")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .menuStyle(.borderedButton)
                } else {
                    Button("settings.faceid.action.addFace") {
                        requestSecurityVerification()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
    }

    private var securityOptionsCard: some View {
        SettingsCard(title: "settings.faceid.card.security") {
            SettingsToggleRow(
                title: "settings.faceid.toggle.requireOpenEyes.title",
                description: "settings.faceid.toggle.requireOpenEyes.desc",
                systemImage: "eye.fill",
                color: .indigo,
                isOn: $settings.requireOpenEyes,
                accessibilityIdentifier: "settings.faceid.requireOpenEyes"
            )

            Divider()
                .opacity(0.6)
                .padding(.leading, 43)

            SettingsToggleRow(
                title: "settings.faceid.toggle.liveness.title",
                description: "settings.faceid.toggle.liveness.desc",
                systemImage: "person.fill.viewfinder",
                color: .teal,
                isOn: $settings.livenessCheck,
                accessibilityIdentifier: "settings.faceid.livenessCheck"
            )

            Divider()
                .opacity(0.6)
                .padding(.leading, 43)

            SettingsToggleRow(
                title: "settings.faceid.toggle.unlockOnWake.title",
                description: "settings.faceid.toggle.unlockOnWake.desc",
                systemImage: "lock.open.fill",
                color: .green,
                isOn: $settings.unlockOnWake,
                accessibilityIdentifier: "settings.faceid.unlockOnWake"
            )

            Divider()
                .opacity(0.6)
                .padding(.leading, 43)

            SettingsToggleRow(
                title: "settings.faceid.toggle.lowLight.title",
                description: "settings.faceid.toggle.lowLight.desc",
                systemImage: "sun.max.fill",
                color: .yellow,
                isOn: $settings.isLowLightAssistEnabled,
                accessibilityIdentifier: "settings.faceid.lowLightAssist"
            )
        }
    }

    private var securityVerificationSheet: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(Color.blue.opacity(0.12))
                    .frame(width: 60, height: 60)

                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(.blue)
            }
            .padding(.top, 4)

            Text("settings.faceid.security.title")
                .font(.system(size: 16, weight: .bold))

            Text("settings.faceid.security.desc")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 10)

            VStack(alignment: .leading, spacing: 6) {
                SecureField("settings.faceid.security.passwordPlaceholder", text: $passwordInput)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 300)
                    .disabled(isVerifyingPassword)
                    .onChange(of: passwordInput) { _, _ in
                        if passwordErrorMessage != nil {
                            passwordErrorMessage = nil
                        }
                    }
                    .onSubmit {
                        confirmSecurityVerification()
                    }

                if let passwordErrorMessage {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 11))
                        Text(passwordErrorMessage)
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundStyle(.red)
                    .frame(maxWidth: 300, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                }
            }

            HStack(spacing: 12) {
                Button("settings.faceid.security.cancel") {
                    passwordInput = ""
                    passwordErrorMessage = nil
                    isVerifyingPassword = false
                    isShowingSecuritySheet = false
                }
                .buttonStyle(.bordered)
                .keyboardShortcut(.cancelAction)
                .disabled(isVerifyingPassword)

                Button(action: {
                    confirmSecurityVerification()
                }) {
                    HStack(spacing: 6) {
                        if isVerifyingPassword {
                            ProgressView()
                                .controlSize(.small)
                            Text("settings.faceid.security.verifying")
                        } else {
                            Text("settings.faceid.security.continue")
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(passwordInput.isEmpty || isVerifyingPassword)
                .keyboardShortcut(.defaultAction)
            }
            .padding(.top, 4)
        }
        .padding(24)
        .frame(width: 390)
    }

    private func requestSecurityVerification() {
        passwordInput = ""
        passwordErrorMessage = nil
        isVerifyingPassword = false
        isShowingSecuritySheet = true
    }

    private func confirmSecurityVerification() {
        let trimmed = passwordInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isVerifyingPassword else { return }

        isVerifyingPassword = true
        passwordErrorMessage = nil

        let enteredPassword = passwordInput
        DispatchQueue.global(qos: .userInitiated).async {
            let isValid = FaceIDKeychainService.verifyPassword(enteredPassword)
            DispatchQueue.main.async {
                isVerifyingPassword = false
                if isValid {
                    _ = FaceIDKeychainService.savePassword(enteredPassword)
                    hasStoredPassword = true
                    passwordInput = ""
                    passwordErrorMessage = nil
                    isShowingSecuritySheet = false

                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        startNotchEnrollment()
                    }
                } else {
                    passwordErrorMessage = L10n.string("settings.faceid.security.invalidPassword", language: applicationSettings.appLanguage)
                }
            }
        }
    }

    private func startNotchEnrollment() {
        guard let notchViewModel else {
            isShowingEnrollmentSheet = true
            return
        }

        let cameraService = FaceIDEnrollmentCameraService()
        let content = FaceIDEnrollmentNotchContent(
            step: .intro,
            settings: settings,
            notchViewModel: notchViewModel,
            cameraService: cameraService
        )
        notchViewModel.send(.showTemporaryNotification(content, duration: 180.0))
    }

    private func testFaceIDInNotch() {
        guard let notchViewModel else { return }

        let content = FaceIDNotchContent(service: service)
        notchViewModel.send(.showTemporaryNotification(content, duration: 8.0))

        service.startScan(
            requireOpenEyes: settings.requireOpenEyes,
            livenessCheck: settings.livenessCheck
        ) { [weak service, weak notchViewModel] _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                notchViewModel?.hideTemporaryNotification()
                service?.cancelScan()
            }
        }
    }
}
