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
    @State private var isShowingPasswordSheet = false
    @State private var hasStoredPassword = FaceIDKeychainService.hasPassword
    @State private var passwordInput = ""

    private func localized(_ key: String, fallback: String? = nil) -> String {
        applicationSettings.appLanguage.locale.dn(key, fallback: fallback)
    }

    var body: some View {
        SettingsPageScrollView {
            faceIDGeneralCard
            faceEnrollmentCard
            passwordCard
            lockScreenCard
            securityOptionsCard
        }
        .sheet(isPresented: $isShowingEnrollmentSheet) {
            FaceIDEnrollmentSheetView(settings: settings, service: service)
        }
        .sheet(isPresented: $isShowingPasswordSheet) {
            passwordEntrySheet
        }
        .confirmationDialog(
            "Сбросить данные Face ID?",
            isPresented: $isShowingResetConfirmation,
            titleVisibility: .visible
        ) {
            Button("Удалить лицо", role: .destructive) {
                settings.resetFace()
            }
            Button("Отмена", role: .cancel) {}
        } message: {
            Text("Биометрический профиль лица будет удален. Для использования Face ID потребуется настроить лицо заново.")
        }
    }

    private var faceIDGeneralCard: some View {
        SettingsCard(title: "Face ID") {
            SettingsToggleRow(
                title: "Использовать Face ID",
                description: "Разблокировка Mac и подтверждение действий с помощью сканирования лица",
                systemImage: "faceid",
                color: .blue,
                isOn: $settings.isFaceIDEnabled,
                accessibilityIdentifier: "settings.faceid.enabled"
            )

            Divider()
                .opacity(0.6)
                .padding(.leading, 43)

            HStack {
                HStack(spacing: 12) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 15))
                        .foregroundStyle(.cyan)
                        .frame(width: 28, height: 28)
                        .background(Color.cyan.opacity(0.12), in: RoundedRectangle(cornerRadius: 7))

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Проверить Face ID в Notch")
                            .font(.system(size: 13, weight: .medium))
                        Text("Запустить сканирование лица камерой в вырезе экрана")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                Button("Проверить") {
                    testFaceIDInNotch()
                }
                .buttonStyle(.bordered)
                .disabled(!settings.isFaceIDEnabled)
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 12)
        }
    }

    private var faceEnrollmentCard: some View {
        SettingsCard(title: "Профиль лица") {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(settings.isEnrolled ? Color.green.opacity(0.15) : Color.orange.opacity(0.15))
                        .frame(width: 44, height: 44)

                    Image(systemName: settings.isEnrolled ? "checkmark.seal.fill" : "person.crop.circle.badge.questionmark")
                        .font(.system(size: 22))
                        .foregroundStyle(settings.isEnrolled ? .green : .orange)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(settings.isEnrolled ? "Лицо зарегистрировано" : "Лицо не настроено")
                        .font(.system(size: 13, weight: .semibold))

                    if settings.isEnrolled && !settings.enrolledDateString.isEmpty {
                        Text("Настроено: \(settings.enrolledDateString)")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Добавьте лицо для быстрого входа в систему")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                if settings.isEnrolled {
                    Menu {
                        Button("Пересканировать лицо") {
                            isShowingEnrollmentSheet = true
                        }
                        Button("Удалить лицо", role: .destructive) {
                            isShowingResetConfirmation = true
                        }
                    } label: {
                        Text("Настроено")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .menuStyle(.borderedButton)
                } else {
                    Button("Настроить") {
                        isShowingEnrollmentSheet = true
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 12)
        }
    }

    private var passwordCard: some View {
        SettingsCard(title: "Разблокировка экрана") {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(hasStoredPassword ? Color.green.opacity(0.15) : Color.orange.opacity(0.15))
                        .frame(width: 44, height: 44)

                    Image(systemName: hasStoredPassword ? "key.fill" : "key.slash.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(hasStoredPassword ? .green : .orange)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(hasStoredPassword ? "Пароль Mac сохранен" : "Пароль Mac не настроен")
                        .font(.system(size: 13, weight: .semibold))

                    Text(hasStoredPassword
                         ? "Пароль зашифрован в Связке ключей macOS для автоматического входа"
                         : "macOS требует пароль для входа. Сохраните его для автоматической разблокировки")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if hasStoredPassword {
                    Menu {
                        Button("Изменить пароль") {
                            passwordInput = ""
                            isShowingPasswordSheet = true
                        }
                        Button("Удалить пароль", role: .destructive) {
                            FaceIDKeychainService.deletePassword()
                            hasStoredPassword = false
                        }
                    } label: {
                        Text("Настроен")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .menuStyle(.borderedButton)
                } else {
                    Button("Указать пароль") {
                        passwordInput = ""
                        isShowingPasswordSheet = true
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 12)
        }
    }

    private var lockScreenCard: some View {
        SettingsCard(title: "Экран блокировки") {
            SettingsToggleRow(
                title: "Кнопка внизу экрана",
                description: "Отображать кнопку быстрого входа через Face ID внизу экрана по центру",
                systemImage: "faceid",
                color: .blue,
                isOn: $settings.showLockScreenButton,
                accessibilityIdentifier: "settings.faceid.showLockScreenButton"
            )
        }
    }

    private var securityOptionsCard: some View {
        SettingsCard(title: "Дополнительная защита") {
            SettingsToggleRow(
                title: "Требовать открытые глаза",
                description: "Предотвращает разблокировку Mac с закрытыми глазами или пока вы спите",
                systemImage: "eye.fill",
                color: .indigo,
                isOn: $settings.requireOpenEyes,
                accessibilityIdentifier: "settings.faceid.requireOpenEyes"
            )

            Divider()
                .opacity(0.6)
                .padding(.leading, 43)

            SettingsToggleRow(
                title: "Проверка живости (Liveness)",
                description: "Защита от сканирования по статичной фотографии или изображению с экрана",
                systemImage: "person.fill.viewfinder",
                color: .teal,
                isOn: $settings.livenessCheck,
                accessibilityIdentifier: "settings.faceid.livenessCheck"
            )

            Divider()
                .opacity(0.6)
                .padding(.leading, 43)

            SettingsToggleRow(
                title: "Сканировать при включении экрана",
                description: "Активировать камеру сразу при нажатии клавиши или пробуждении заблокированного Mac",
                systemImage: "lock.open.fill",
                color: .green,
                isOn: $settings.unlockOnWake,
                accessibilityIdentifier: "settings.faceid.unlockOnWake"
            )

            Divider()
                .opacity(0.6)
                .padding(.leading, 43)

            SettingsToggleRow(
                title: "Подсветка в темноте",
                description: "Кратковременно подсвечивать экран белым при недостаточном освещении",
                systemImage: "sun.max.fill",
                color: .yellow,
                isOn: $settings.isLowLightAssistEnabled,
                accessibilityIdentifier: "settings.faceid.lowLightAssist"
            )
        }
    }

    private var passwordEntrySheet: some View {
        VStack(spacing: 16) {
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 38))
                .foregroundStyle(.blue)

            Text("Пароль учетной записи Mac")
                .font(.system(size: 16, weight: .bold))

            Text("В macOS нет API для разблокировки без пароля. Как и в проектах Glance и FaceUnlock, пароль безопасно сохраняется в вашей системной Связке ключей (Keychain) и вводится автоматически при успешном подтверждении лица.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 8)

            SecureField("Введите пароль от вашей учетной записи Mac", text: $passwordInput)
                .textFieldStyle(.roundedBorder)
                .frame(width: 300)

            HStack(spacing: 12) {
                Button("Отмена") {
                    isShowingPasswordSheet = false
                }
                .buttonStyle(.bordered)
                .keyboardShortcut(.cancelAction)

                Button("Сохранить в Keychain") {
                    if !passwordInput.isEmpty {
                        _ = FaceIDKeychainService.savePassword(passwordInput)
                        hasStoredPassword = true
                        isShowingPasswordSheet = false
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(passwordInput.isEmpty)
                .keyboardShortcut(.defaultAction)
            }
            .padding(.top, 4)
        }
        .padding(24)
        .frame(width: 380)
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
