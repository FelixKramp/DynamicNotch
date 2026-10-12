//
//  LockScreenFaceIDButtonView.swift
//  DynamicNotch
//

import SwiftUI

struct LockScreenFaceIDButtonView: View {
    @ObservedObject var service: FaceIDService = .shared
    
    let faceIDSettings: FaceIDSettingsStore
    let onActivate: () -> Void

    private var state: FaceIDState {
        service.state
    }

    var body: some View {
        Button(action: onActivate) {
            HStack(spacing: 6) {
                Image(systemName: "faceid")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Color.white.opacity(0.8))
                
                Text(verbatim: "Face ID")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.8))
            }
            .padding(6)
            .background(
                Capsule()
                    .fill(.ultraThinMaterial)
                    .stroke(.gray.opacity(0.15), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}
