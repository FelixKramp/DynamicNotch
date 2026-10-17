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
            Image(systemName: "network.badge.shield.half.filled")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.green)
            
            Spacer()
            
            Text(timeString)
                .monospacedDigit()
                .foregroundStyle(.orange.gradient)
        }
        .font(.system(size: isNotchlessScreen ? 13 : 14))
        .padding(.leading, isNotchlessScreen ? 4.scaled(by: scale) : 14.scaled(by: scale))
        .padding(.trailing, isNotchlessScreen ? 7.scaled(by: scale) : 14.scaled(by: scale))
        .onReceive(timer) { _ in
            updateTimer()
        }
        .onAppear {
            updateTimer()
        }
    }
}
