//
//  SystemSettingsVpnMonitor.swift
//  DynamicNotch
//

internal import AppKit
import ApplicationServices
import Combine
import Foundation

@MainActor
final class SystemSettingsVpnMonitor: ObservableObject {
    @Published private(set) var isVpnTabOpen: Bool = false

    private var pollTimer: Timer?
    private var cancellables = Set<AnyCancellable>()

    init() {
        setupObservers()
        checkState()
    }

    private func setupObservers() {
        let center = NSWorkspace.shared.notificationCenter

        center.publisher(for: NSWorkspace.didLaunchApplicationNotification)
            .sink { [weak self] note in
                if self?.isSystemSettingsApp(note) == true {
                    self?.startPolling()
                    self?.checkState()
                }
            }
            .store(in: &cancellables)

        center.publisher(for: NSWorkspace.didTerminateApplicationNotification)
            .sink { [weak self] note in
                if self?.isSystemSettingsApp(note) == true {
                    self?.stopPolling()
                    self?.updateState(false)
                }
            }
            .store(in: &cancellables)

        center.publisher(for: NSWorkspace.didActivateApplicationNotification)
            .sink { [weak self] _ in
                self?.checkState()
            }
            .store(in: &cancellables)

        center.publisher(for: NSWorkspace.didDeactivateApplicationNotification)
            .sink { [weak self] _ in
                self?.checkState()
            }
            .store(in: &cancellables)

        center.publisher(for: NSWorkspace.didHideApplicationNotification)
            .sink { [weak self] _ in
                self?.checkState()
            }
            .store(in: &cancellables)

        center.publisher(for: NSWorkspace.didUnhideApplicationNotification)
            .sink { [weak self] _ in
                self?.checkState()
            }
            .store(in: &cancellables)

        if isSystemSettingsRunning() {
            startPolling()
        }
    }

    private func isSystemSettingsApp(_ note: Notification) -> Bool {
        guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else {
            return false
        }
        return app.bundleIdentifier == "com.apple.systempreferences"
    }

    private func isSystemSettingsRunning() -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.systempreferences").isEmpty
    }

    private func startPolling() {
        guard pollTimer == nil else { return }
        pollTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.checkState()
            }
        }
    }

    private func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    func checkState() {
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.systempreferences").first else {
            stopPolling()
            updateState(false)
            return
        }

        if app.isHidden {
            updateState(false)
            return
        }

        if pollTimer == nil {
            startPolling()
        }

        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        var windowsRef: AnyObject?
        guard AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsRef) == .success,
              let windows = windowsRef as? [AXUIElement] else {
            updateState(false)
            return
        }

        for window in windows {
            var minimizedRef: AnyObject?
            AXUIElementCopyAttributeValue(window, kAXMinimizedAttribute as CFString, &minimizedRef)
            if (minimizedRef as? Bool) == true {
                continue
            }

            var titleRef: AnyObject?
            if AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &titleRef) == .success,
               let title = titleRef as? String {
                if title == "VPN" || title.localizedCaseInsensitiveContains("VPN") {
                    updateState(true)
                    return
                }
            }
        }

        updateState(false)
    }

    private func updateState(_ newValue: Bool) {
        if isVpnTabOpen != newValue {
            isVpnTabOpen = newValue
        }
    }

    deinit {
        pollTimer?.invalidate()
    }
}
