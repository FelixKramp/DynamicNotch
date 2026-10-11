//
//  LockScreenFaceIDWindowManager.swift
//  DynamicNotch
//

internal import AppKit
import Combine
import SwiftUI

@MainActor
final class LockScreenFaceIDWindowManager {
    private static let windowSize = CGSize(width: 220, height: 48)

    private let lockScreenManager: LockScreenManager
    private let faceIDSettings: FaceIDSettingsStore
    private let settingsViewModel: SettingsViewModel
    private let notchViewModel: NotchViewModel
    private let faceIDService: FaceIDService

    private var buttonWindow: OverlayPanelWindow?
    private var hostingView: NotchHostingView?
    private var hasDelegatedWindow = false
    private var appObservers: [NSObjectProtocol] = []
    private var workspaceObservers: [NSObjectProtocol] = []
    private var cancellables = Set<AnyCancellable>()

    init(
        lockScreenManager: LockScreenManager,
        faceIDSettings: FaceIDSettingsStore,
        settingsViewModel: SettingsViewModel,
        notchViewModel: NotchViewModel,
        faceIDService: FaceIDService? = nil
    ) {
        self.lockScreenManager = lockScreenManager
        self.faceIDSettings = faceIDSettings
        self.settingsViewModel = settingsViewModel
        self.notchViewModel = notchViewModel
        self.faceIDService = faceIDService ?? .shared

        bindState()
        registerObservers()
    }

    func invalidate() {
        appObservers.forEach(NotificationCenter.default.removeObserver)
        appObservers.removeAll()

        let workspaceCenter = NSWorkspace.shared.notificationCenter
        workspaceObservers.forEach(workspaceCenter.removeObserver)
        workspaceObservers.removeAll()

        cancellables.removeAll()
        releaseButtonResources()
    }

    private func bindState() {
        Publishers.CombineLatest(
            Publishers.CombineLatest3(
                lockScreenManager.$isLocked.removeDuplicates(),
                lockScreenManager.$isPreparingLock.removeDuplicates(),
                lockScreenManager.$didUnlockWithFaceID.removeDuplicates()
            ),
            Publishers.CombineLatest(
                lockScreenManager.$isLockIdle.removeDuplicates(),
                faceIDSettings.$showLockScreenButton.removeDuplicates()
            )
        )
        .receive(on: RunLoop.main)
        .sink { [weak self] lockState, settingsState in
            let (isLocked, isPreparingLock, _) = lockState
            let (isLockIdle, showButton) = settingsState
            self?.syncPresentation(
                isLocked: isLocked,
                isPreparingLock: isPreparingLock,
                isLockIdle: isLockIdle,
                showButton: showButton
            )
        }
        .store(in: &cancellables)

        Publishers.CombineLatest(
            faceIDSettings.$isFaceIDEnabled.removeDuplicates(),
            faceIDSettings.$isEnrolled.removeDuplicates()
        )
        .receive(on: RunLoop.main)
        .sink { [weak self] _, _ in
            self?.syncCurrentPresentation()
            self?.refreshPosition(animated: false)
        }
        .store(in: &cancellables)

        faceIDService.$state
            .receive(on: RunLoop.main)
            .sink { [weak self] state in
                guard let self else { return }
                if state.isActivelyEvaluating || state.isSuccess || state.isFailed {
                    self.notchViewModel.send(.showLiveActivity(FaceIDNotchContent(service: self.faceIDService)))
                } else if state == .idle {
                    self.notchViewModel.send(.hideLiveActivity(id: NotchContentRegistry.FaceID.scanning.id))
                }
            }
            .store(in: &cancellables)
    }

    private func registerObservers() {
        let center = NotificationCenter.default
        appObservers.append(
            center.addObserver(
                forName: NSApplication.didChangeScreenParametersNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.refreshPosition(animated: false)
                }
            }
        )

        let workspaceCenter = NSWorkspace.shared.notificationCenter
        workspaceObservers.append(
            workspaceCenter.addObserver(
                forName: NSWorkspace.screensDidWakeNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.refreshPosition(animated: false)
                    self.handleScreenWake()
                }
            }
        )
    }

    private func handleScreenWake() {
        guard lockScreenManager.isShowingLockPresentation,
              faceIDSettings.isFaceIDEnabled,
              faceIDSettings.isEnrolled,
              faceIDSettings.unlockOnWake else {
            return
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            guard let self, self.lockScreenManager.isShowingLockPresentation else { return }
            self.activateFaceID()
        }
    }

    private func syncCurrentPresentation() {
        syncPresentation(
            isLocked: lockScreenManager.isLocked,
            isPreparingLock: lockScreenManager.isPreparingLock,
            isLockIdle: lockScreenManager.isLockIdle,
            showButton: faceIDSettings.showLockScreenButton
        )
    }

    private func syncPresentation(
        isLocked: Bool,
        isPreparingLock: Bool,
        isLockIdle: Bool,
        showButton: Bool
    ) {
        let isShowingLock = isLocked && !lockScreenManager.didUnlockWithFaceID
        let isAvailable = faceIDSettings.isFaceIDEnabled && faceIDSettings.isEnrolled

        if isShowingLock && isAvailable && showButton {
            presentButton()
        } else {
            hideButton()
        }
    }

    private func presentButton() {
        guard let screen = currentScreen() else { return }

        let window = makeWindowIfNeeded(for: screen)
        let targetFrame = buttonFrame(for: screen)

        if window.frame != targetFrame {
            window.setFrame(targetFrame, display: true)
        }

        let buttonView = LockScreenFaceIDButtonView(
            faceIDSettings: faceIDSettings,
            onActivate: { [weak self] in
                self?.activateFaceID()
            }
        )

        let rootView = ZStack {
            buttonView
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)

        if let hostingView {
            hostingView.rootView = AnyView(rootView)
            hostingView.frame = NSRect(origin: .zero, size: targetFrame.size)
        } else {
            let hostingView = NotchHostingView(rootView: rootView)
            hostingView.frame = NSRect(origin: .zero, size: targetFrame.size)
            hostingView.autoresizingMask = [.width, .height]
            self.hostingView = hostingView
            window.contentView = hostingView
        }

        if let hostingView, window.contentView !== hostingView {
            window.contentView = hostingView
        }

        if !hasDelegatedWindow {
            SkyLightOperator.shared.delegateWindow(window, to: .lockScreenOverlay)
            hasDelegatedWindow = true
        }

        window.orderFrontRegardless()
    }

    private func hideButton() {
        buttonWindow?.orderOut(nil)
    }

    private func releaseButtonResources() {
        buttonWindow?.orderOut(nil)
        buttonWindow?.contentView = nil
        hostingView = nil
        buttonWindow = nil
        hasDelegatedWindow = false
    }

    private func refreshPosition(animated: Bool) {
        guard let window = buttonWindow, window.isVisible, let screen = currentScreen() else {
            return
        }

        let targetFrame = buttonFrame(for: screen)

        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.2
                window.animator().setFrame(targetFrame, display: true)
            }
        } else {
            window.setFrame(targetFrame, display: true)
        }
    }

    func activateFaceID() {
        guard faceIDService.state == .idle || faceIDService.state.isFailed else { return }

        let requireEyes = faceIDSettings.requireOpenEyes
        let liveness = faceIDSettings.livenessCheck

        // Show FaceIDNotchContent view when Face ID triggers
        notchViewModel.send(.showLiveActivity(
            FaceIDNotchContent(service: faceIDService)
        ))

        faceIDService.startScan(
            requireOpenEyes: requireEyes,
            livenessCheck: liveness
        ) { [weak self] success in
            guard let self else { return }
            if success {
                self.hideButton()
                self.lockScreenManager.handleFaceIDUnlock()
                self.notchViewModel.send(.hideLiveActivity(id: NotchContentRegistry.LockScreen.activity.id))
                FaceIDService.shared.unlockWithSavedPassword()

                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
                    self?.notchViewModel.send(.hideLiveActivity(id: NotchContentRegistry.FaceID.scanning.id))
                    self?.faceIDService.cancelScan()
                }
            } else {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) { [weak self] in
                    self?.notchViewModel.send(.hideLiveActivity(id: NotchContentRegistry.FaceID.scanning.id))
                    self?.faceIDService.cancelScan()
                }
            }
        }
    }

    private func makeWindowIfNeeded(for screen: NSScreen) -> OverlayPanelWindow {
        if let buttonWindow {
            return buttonWindow
        }

        let window = OverlayPanelFactory.makePanel(
            frame: buttonFrame(for: screen),
            level: OverlayWindowLevel.lockScreenNotch
        )

        buttonWindow = window
        return window
    }

    private func currentScreen() -> NSScreen? {
        NSScreen.preferredLockScreen ??
        NSScreen.preferredNotchScreen(for: settingsViewModel) ??
        NSScreen.main ??
        NSScreen.screens.first
    }

    private func buttonFrame(for screen: NSScreen) -> NSRect {
        let size = Self.windowSize
        let x = floor(screen.frame.midX - size.width / 2)
        let y = screen.frame.minY + 10

        return NSRect(origin: CGPoint(x: x, y: y), size: size)
    }
}
