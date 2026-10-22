//
//  SoftwareUpdateNotchView.swift
//  DynamicNotch
//
//  Created by Евгений Петрукович on 7/17/26.
//

import SwiftUI

struct SoftwareUpdateNotchView: View {
    @Environment(\.notchScale) private var scale
    @Environment(\.isNotchlessScreen) private var isNotchlessScreen
    
    var body: some View {
        HStack {
            Image("logo")
                .resizable()
                .interpolation(.high)
                .antialiased(true)
                .scaledToFill()
                .frame(width: isNotchlessScreen ? 20 : 24, height: isNotchlessScreen ? 20 : 24)
                .cornerRadius(6)
            
            Spacer()
            
            Image(systemName: "arrow.down.circle.dotted")
                .font(.system(size: isNotchlessScreen ? 18 : 21, weight: .semibold))
                .foregroundStyle(.blue)
        }
        .padding(.leading, isNotchlessScreen ? 6.scaled(by: scale) : 13.scaled(by: scale))
        .padding(.trailing, isNotchlessScreen ? 4.scaled(by: scale) : 11.scaled(by: scale))
    }
}
