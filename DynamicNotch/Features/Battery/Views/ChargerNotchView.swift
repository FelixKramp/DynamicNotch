//
//  ChargerNotchView.swift
//  DynamicNotch
//
//  Created by Евгений Петрукович on 4/14/26.
//

import SwiftUI

struct ChargerNotchView: View {
    @Environment(\.locale) private var locale
    @ObservedObject var powerService: PowerService
    
    private var batteryColor: Color {
        if powerService.isLowPowerMode {
            return .yellow
        } else if powerService.batteryLevel <= 20 {
            return .red
        } else {
            return .green
        }
    }
    
    var body: some View {
        BatteryCompactStatusView(
            title: locale.dn("notch.battery.charging", fallback: "Charging"),
            batteryLevel: powerService.batteryLevel,
            tint: batteryColor
        )
    }
}
