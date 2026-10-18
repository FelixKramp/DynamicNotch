//
//  VpnSettingsView.swift
//  DynamicNotch
//
//  Created by Евгений Петрукович on 6/19/26.
//

import SwiftUI
import Combine
internal import AppKit

struct VpnSettingsView: View {
    @ObservedObject var connectivitySettings: ConnectivitySettingsStore
    @ObservedObject var appearanceSettings: ApplicationSettingsStore
    @StateObject private var vpnViewModel = VpnViewModel()
    
    private var temporaryActivityDurationRange: ClosedRange<Double> {
        Double(SettingsStoreBase.temporaryActivityDurationRange.lowerBound)...Double(SettingsStoreBase.temporaryActivityDurationRange.upperBound)
    }
    
    var body: some View {
        SettingsPageScrollView {
            vpnActivity
            vpnDuration
        }
        .onAppear {
            vpnViewModel.startMonitoring()
        }
        .onDisappear {
            vpnViewModel.stopMonitoring()
        }
    }
    
    private var vpnActivity: some View {
        SettingsCard(title: "settings.vpn.card.activity") {
            SettingsToggleRow(
                title: "settings.vpn.temporaryActivity.title",
                description: "settings.vpn.temporaryActivity2.desc",
                systemImage: "network.badge.shield.half.filled",
                color: .blue,
                isOn: $connectivitySettings.isVpnTemporaryActivityEnabled,
                accessibilityIdentifier: "settings.activities.temporary.vpn"
            )

            Divider()
                .opacity(0.6)
                .padding(.leading, 43)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)

            SettingsToggleRow(
                title: "settings.vpn.disconnectedActivity.title",
                description: "settings.vpn.disconnectedActivity2.desc",
                systemImage: "network.slash",
                color: .red,
                isOn: $connectivitySettings.isVpnDisconnectedTemporaryActivityEnabled,
                accessibilityIdentifier: "settings.activities.temporary.vpnDisconnected"
            )
        }
    }
    
    private var vpnDuration: some View {
        SettingsCard(title: "settings.vpn.card.duration") {
            SettingsSliderRow(
                title: "settings.vpn.duration.title",
                description: "settings.vpn.duration2.desc",
                range: temporaryActivityDurationRange,
                step: 1,
                fractionLength: 0,
                suffix: "s",
                accessibilityIdentifier: "settings.activities.temporary.vpn.duration",
                value: Binding(
                    get: { Double(connectivitySettings.vpnTemporaryActivityDuration) },
                    set: { connectivitySettings.vpnTemporaryActivityDuration = Int($0.rounded()) }
                )
            )
            .disabled(!connectivitySettings.isVpnTemporaryActivityEnabled)
            .opacity(connectivitySettings.isVpnTemporaryActivityEnabled ? 1 : 0.5)

            Divider()
                .opacity(0.6)

            SettingsSliderRow(
                title: "settings.vpn.disconnectedDuration.title",
                description: "settings.vpn.disconnectedDuration2.desc",
                range: temporaryActivityDurationRange,
                step: 1,
                fractionLength: 0,
                suffix: "s",
                accessibilityIdentifier: "settings.activities.temporary.vpnDisconnected.duration",
                value: Binding(
                    get: { Double(connectivitySettings.vpnDisconnectedTemporaryActivityDuration) },
                    set: { connectivitySettings.vpnDisconnectedTemporaryActivityDuration = Int($0.rounded()) }
                )
            )
            .disabled(!connectivitySettings.isVpnDisconnectedTemporaryActivityEnabled)
            .opacity(connectivitySettings.isVpnDisconnectedTemporaryActivityEnabled ? 1 : 0.5)
        }
    }
}

struct VPNStatusRowView: View {
    let isConnected: Bool
    let connectedAt: Date?
    
    @Environment(\.locale) private var locale
    @State private var elapsedString: String = "00:00"
    
    private let timer = Timer.publish(every: 1.0, on: .main, in: .common).autoconnect()
    
    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(isConnected ? Color.green : Color.red)
                .frame(width: 8, height: 8)
            
            Text(statusText)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .onReceive(timer) { _ in
            updateElapsed()
        }
        .onAppear {
            updateElapsed()
        }
        .onChange(of: isConnected) { _, _ in
            updateElapsed()
        }
        .onChange(of: connectedAt) { _, _ in
            updateElapsed()
        }
    }
    
    private var statusText: String {
        let isRussian = locale.identifier.hasPrefix("ru")
        let isSpanish = locale.identifier.hasPrefix("es")
        let isChinese = locale.identifier.hasPrefix("zh")
        
        if isConnected {
            if isRussian {
                return "подключен в течение \(elapsedString)"
            } else if isSpanish {
                return "conectado durante \(elapsedString)"
            } else if isChinese {
                return "已连接 \(elapsedString)"
            } else {
                return "connected for \(elapsedString)"
            }
        } else {
            if isRussian {
                return "отключено"
            } else if isSpanish {
                return "desconectado"
            } else if isChinese {
                return "未连接"
            } else {
                return "disconnected"
            }
        }
    }
    
    private func updateElapsed() {
        guard isConnected, let connectedAt = connectedAt else {
            elapsedString = "00:00"
            return
        }
        let elapsed = Date().timeIntervalSince(connectedAt)
        elapsedString = elapsed.formattedDuration
    }
}
