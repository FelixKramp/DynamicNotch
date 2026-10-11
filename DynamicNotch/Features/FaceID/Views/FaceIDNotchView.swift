//
//  FaceIDNotchView.swift
//  DynamicNotch
//

import SwiftUI

struct FaceIDNotchView: View {
    @Environment(\.isNotchlessScreen) private var isNotchlessScreen
    @ObservedObject var service: FaceIDService = .shared

    @State private var pulseScale: CGFloat = 1.0
    @State private var pulseOpacity: Double = 1.0

    private var currentMedia: ScanMedia {
        if service.state.isSuccess {
            return .success
        } else if service.state.isFailed {
            return .failure
        } else {
            return .idle
        }
    }

    private var headlineColor: Color {
        switch service.state {
        case .searching, .scanning, .success:
            return .green
        case .failed:
            return .red
        default:
            return .green
        }
    }

    var body: some View {
        VStack {
            Spacer()

            ScanAnimationView(media: currentMedia, tintColor: headlineColor)
                .frame(width: 86, height: 86)
                .scaleEffect(pulseScale)
                .opacity(pulseOpacity)

            Spacer()
        }
        .onAppear {
            updatePulsing(for: service.state)
        }
        .onChange(of: service.state) { _, newState in
            updatePulsing(for: newState)
        }
    }

    private func updatePulsing(for state: FaceIDState) {
        if state.isSuccess || state.isFailed {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                pulseScale = 1.0
                pulseOpacity = 1.0
            }
        } else {
            pulseScale = 0.94
            pulseOpacity = 0.85
            withAnimation(.easeInOut(duration: 0.85).repeatForever(autoreverses: true)) {
                pulseScale = 1.04
                pulseOpacity = 1.0
            }
        }
    }
}
