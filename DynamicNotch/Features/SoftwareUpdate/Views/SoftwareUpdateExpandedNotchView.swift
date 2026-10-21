//
//  SoftwareUpdateExpandedNotchView.swift
//  DynamicNotch
//
//  Created by Евгений Петрукович on 10/21/26.
//

import SwiftUI

struct SoftwareUpdateExpandedNotchView: View {
    @Environment(\.isNotchlessScreen) private var isNotchlessScreen
    @ObservedObject private var updater = SparkleUpdater.shared
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Spacer()
            
            HStack(alignment: .center, spacing: 12) {
                Image("logo")
                    .resizable()
                    .interpolation(.high)
                    .antialiased(true)
                    .scaledToFill()
                    .frame(width: 50, height: 50)
                    .cornerRadius(12)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: "Update Available")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.white)
                    
                    Text(verbatim: "Version \(updater.latestVersionString)")
                        .font(.system(size: 14))
                        .foregroundColor(.white.opacity(0.6))
                }
                .padding(.top, isNotchlessScreen ? 6 : 0)
                
                Spacer()
                
                Button(action: {
                    updater.checkForUpdates()
                }) {
                    Image(systemName: "arrow.down.circle.dotted")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(.blue)
                }
                .buttonStyle(PrimaryButtonStyle(width: 50, height: 50, backgroundColor: .blue.opacity(0.25)))
            }
        }
        .padding(.horizontal, isNotchlessScreen ? 20 : 38)
        .padding(.bottom, isNotchlessScreen ? 20 : 14)
    }
}
