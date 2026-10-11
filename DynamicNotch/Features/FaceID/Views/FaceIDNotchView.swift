//
//  FaceIDNotchView.swift
//  DynamicNotch
//

import SwiftUI

struct FaceIDNotchView: View {
    @Environment(\.isNotchlessScreen) private var isNotchlessScreen
    @ObservedObject var service: FaceIDService = .shared
    
    @State private var pulseOpacity: CGFloat = 1.0
    @State private var pulseScale: CGFloat = 1.0

    var body: some View {
        VStack {
            Spacer()

            Image(systemName: "faceid")
                .foregroundStyle(headlineColor)
                .font(.system(size: 90))
                .scaleEffect(pulseScale)
                .opacity(pulseOpacity)
                .symbolEffect(.pulse, options: .repeating, isActive: !service.state.isSuccess && !service.state.isFailed)
            
            Spacer()
        }
        .onAppear {
            startPulsing()
        }
        .onChange(of: service.state) { _, newState in
            if newState.isSuccess || newState.isFailed {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                    pulseScale = 1.0
                    pulseOpacity = 1.0
                }
            } else {
                startPulsing()
            }
        }
    }

    private func startPulsing() {
        guard !service.state.isSuccess && !service.state.isFailed else { return }
        pulseScale = 0.94
        pulseOpacity = 0.75
        withAnimation(.easeInOut(duration: 0.85).repeatForever(autoreverses: true)) {
            pulseScale = 1.06
            pulseOpacity = 1.0
        }
    }

    private var headlineColor: Color {
        switch service.state {
        case .success:
            return .green
        case .failed:
            return .red
        default:
            return .green
        }
    }
}
