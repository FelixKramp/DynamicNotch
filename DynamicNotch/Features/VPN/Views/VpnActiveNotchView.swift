//
//  VpnActiveNotchView.swift
//  DynamicNotch
//

import SwiftUI
import Combine

struct VpnActiveNotchView: View {
    @Environment(\.notchScale) var scale
    @Environment(\.isNotchlessScreen) var isNotchlessScreen
    @ObservedObject var vpnViewModel: VpnViewModel
    
    @State private var timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    @State private var timeString: String = "00:00"
    
    private func updateTimer() {
        guard let startDate = vpnViewModel.vpnConnectedAt else {
            timeString = "00:00"
            return
        }
        let elapsed = Date().timeIntervalSince(startDate)
        timeString = elapsed.formattedDuration
    }
    
    var body: some View {
        HStack {
            if let bandleVpn = vpnViewModel.vpnBundleID, let nsImage = getAppIcon(for: bandleVpn) {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: isNotchlessScreen ? 22 : 26, height: isNotchlessScreen ? 22 : 26)
                    .cornerRadius(8)
            }
            
            Spacer()
            
            Text(timeString)
                .monospacedDigit()
                .foregroundStyle(.orange.gradient)
        }
        .font(.system(size: isNotchlessScreen ? 13 : 14))
        .padding(.leading, isNotchlessScreen ? 5.scaled(by: scale) : 12.scaled(by: scale))
        .padding(.trailing, isNotchlessScreen ? 7.scaled(by: scale) : 15.scaled(by: scale))
        .onReceive(timer) { _ in
            updateTimer()
        }
        .onAppear {
            vpnViewModel.startMonitoring()
            updateTimer()
        }
        .onDisappear {
            vpnViewModel.stopMonitoring()
        }
        .onChange(of: vpnViewModel.vpnConnectedAt) { _, _ in
            updateTimer()
        }
    }
    
    @ViewBuilder
    private func logoOrFlag(for vpn: VPNConfiguration) -> some View {
        if let flag = vpnViewModel.countryFlag ?? vpnViewModel.inferredFlag(for: vpn) {
            Text(flag)
                .font(.system(size: isNotchlessScreen ? 24 : 28))
        } else {
            Image(systemName: "globe.europe.africa.fill")
                .font(.system(size: isNotchlessScreen ? 16 : 18, weight: .semibold))
                .foregroundStyle(.white.opacity(0.6))
        }
    }
    
    private func getAppIcon(for bundleID: String) -> NSImage? {
        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            return nil
        }
        return NSWorkspace.shared.icon(forFile: appURL.path)
    }
}
