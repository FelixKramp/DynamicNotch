//
//  VpnExpandedNotchView.swift
//  DynamicNotch
//
//  Created by Евгений Петрукович on 6/19/26.
//

import SwiftUI
import Combine
internal import AppKit

struct VpnExpandedNotchView: View {
    let notchViewModel: NotchViewModel
    @ObservedObject var viewModel: VpnViewModel
    
    @Environment(\.isNotchlessScreen) private var isNotchlessScreen
    @Environment(\.notchScale) private var notchScale
    @State private var timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    @State private var timeString: String = "00:00"
    
    private func updateTimer() {
        guard let startDate = viewModel.connectedAt else {
            timeString = "00:00"
            return
        }
        let elapsed = Date().timeIntervalSince(startDate)
        timeString = elapsed.formattedDuration
    }
    
    var body: some View {
        VStack {
            Spacer()
            featuredVPNView()
        }
        .padding(.leading, isNotchlessScreen ? 15 : 40)
        .padding(.trailing, isNotchlessScreen ? 15 : 34)
        .padding(.bottom, isNotchlessScreen ? 17 : 12)
        .onReceive(timer) { _ in
            updateTimer()
        }
        .onAppear {
            viewModel.startMonitoring()
            updateTimer()
        }
        .onDisappear {
            viewModel.stopMonitoring()
        }
        .onChange(of: viewModel.connectedAt) { _, _ in
            updateTimer()
        }
    }
    
    @ViewBuilder
    private func featuredVPNView() -> some View {
        if let vpn = viewModel.vpns.first(where: { $0.isConnected }) {
            HStack(spacing: 14) {
                logoOrFlag(for: vpn)
                
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(verbatim: "IP:")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.5))
                        
                        Text(vpnTitle(for: vpn))
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                    }
                    
                    HStack(spacing: 6) {
                        Circle()
                            .fill(.green)
                            .frame(width: 10, height: 10)
                        
                        Text(verbatim: "Сonnected (\(timeString))")
                            .font(.system(size: 14))
                            .foregroundStyle(.white.opacity(0.5))
                            .lineLimit(1)
                    }
                }
                Spacer()
                
                Button(action: {
                    viewModel.toggleVPN(vpn)
                    notchViewModel.send(.hideLiveActivity(id: NotchContentRegistry.Vpn.vpn.id))
                }) {
                    Image(systemName: "network.slash")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(.red)
                }
                .buttonStyle(PrimaryButtonStyle(width: 50, height: 50, backgroundColor: .red.opacity(0.25)))
            }
        }
    }
    
    private func vpnTitle(for vpn: VPNConfiguration) -> String {
        if vpn.isConnected {
            if let ip = viewModel.currentIP, !ip.isEmpty {
                return ip
            } else if let serverAddress = vpn.serverAddress, !serverAddress.isEmpty {
                return serverAddress
            }
        }
        return vpn.name
    }
    
    @ViewBuilder
    private func logoOrFlag(for vpn: VPNConfiguration) -> some View {
        if let flag = viewModel.countryFlag ?? viewModel.inferredFlag(for: vpn) {
            Text(flag)
                .font(.system(size: 48))
        } else {
            Image(systemName: "globe.europe.africa.fill")
                .font(.system(size: 40, weight: .semibold))
                .foregroundStyle(.white.opacity(0.6))
        }
    }
}
