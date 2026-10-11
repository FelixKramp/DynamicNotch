//
//  FaceIDPureAnimationView.swift
//  DynamicNotch
//
//  A 100% native SwiftUI recreation of Apple's Face ID scanning animation:
//  - Starts with the authentic Apple SF Symbol `faceid`
//  - Morphs into a 3D rotating spherical wireframe (gyroscope) during scanning
//  - Smoothly aligns and transitions into a bounded circle with a dynamically drawn checkmark upon success
//  - Shakes in red upon failure
//  - Fully customizable color
//

import SwiftUI

struct FaceIDPureAnimationView: View {
    let state: FaceIDState
    var color: Color = .green
    var size: CGFloat = 84

    @State private var phase: FaceIDPhase = .idle
    @State private var rotationAngle: Double = 0.0
    @State private var checkmarkProgress: CGFloat = 0.0
    @State private var successBounce: CGFloat = 1.0
    @State private var shakeOffset: CGFloat = 0.0
    @State private var pulseScale: CGFloat = 1.0
    @State private var pulseOpacity: Double = 1.0

    private enum FaceIDPhase: Equatable {
        case idle
        case scanning
        case success
        case failed
    }

    var body: some View {
        ZStack {
            // MARK: - Phase 1 & 4: Apple Native Face ID Glyph (Idle & Failed)
            if phase == .idle || phase == .failed {
                Image(systemName: "faceid")
                    .font(.system(size: size * 0.92, weight: .regular))
                    .foregroundStyle(phase == .failed ? Color.red : color)
                    .scaleEffect(phase == .idle ? pulseScale : 1.0)
                    .opacity(phase == .idle ? pulseOpacity : 1.0)
                    .transition(.opacity.combined(with: .scale(scale: 0.88)))
            }

            // MARK: - Phase 2: 3D Wireframe Gyroscope (Scanning)
            if phase == .scanning {
                gyroscopeScanningView
                    .transition(.opacity.combined(with: .scale(scale: 1.1)))
            }

            // MARK: - Phase 3: Circle & Checkmark (Success)
            if phase == .success {
                successCheckmarkView
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
            }
        }
        .frame(width: size, height: size)
        .offset(x: shakeOffset)
        .onAppear {
            handleStateTransition(to: state, animated: false)
        }
        .onChange(of: state) { _, newState in
            handleStateTransition(to: newState, animated: true)
        }
    }

    // MARK: - 3D Gyroscope Scanning View

    private var gyroscopeScanningView: some View {
        ZStack {
            // Soft atmospheric depth glow
            Circle()
                .fill(
                    RadialGradient(
                        colors: [color.opacity(0.24), color.opacity(0.0)],
                        center: .center,
                        startRadius: 0,
                        endRadius: size * 0.52
                    )
                )
                .frame(width: size, height: size)

            // Faint outer bounding sphere rim
            Circle()
                .stroke(color.opacity(0.32), lineWidth: 2.2)
                .frame(width: size * 0.94, height: size * 0.94)
                .blur(radius: 0.6)

            // Primary orbital ring 1 (tilted longitude)
            Circle()
                .stroke(color, lineWidth: 4.8)
                .frame(width: size * 0.94, height: size * 0.94)
                .rotation3DEffect(
                    .degrees(rotationAngle),
                    axis: (x: 0.35, y: 1.0, z: 0.15),
                    perspective: 0.55
                )

            // Primary orbital ring 2 (orthogonal transverse orbit)
            Circle()
                .stroke(color.opacity(0.85), lineWidth: 4.2)
                .frame(width: size * 0.94, height: size * 0.94)
                .rotation3DEffect(
                    .degrees(rotationAngle + 65),
                    axis: (x: -0.55, y: 0.9, z: -0.25),
                    perspective: 0.55
                )

            // Inner orbital ring 3 (equatorial diagonal orbit)
            Circle()
                .stroke(color.opacity(0.55), lineWidth: 3.0)
                .frame(width: size * 0.88, height: size * 0.88)
                .rotation3DEffect(
                    .degrees(rotationAngle * 1.35),
                    axis: (x: 1.0, y: 0.25, z: 0.4),
                    perspective: 0.55
                )
        }
    }

    // MARK: - Success Circle & Checkmark View

    private var successCheckmarkView: some View {
        ZStack {
            // Solid outer circle
            Circle()
                .stroke(color, lineWidth: 5.6)
                .frame(width: size * 0.94, height: size * 0.94)

            // Vector checkmark matching Apple's Face ID geometry
            FaceIDCheckmarkShape()
                .trim(from: 0, to: checkmarkProgress)
                .stroke(
                    color,
                    style: StrokeStyle(lineWidth: 5.8, lineCap: .round, lineJoin: .round)
                )
                .frame(width: size * 0.94, height: size * 0.94)
        }
        .scaleEffect(successBounce)
    }

    // MARK: - State Handling & Animation Orchestration

    private func handleStateTransition(to newState: FaceIDState, animated: Bool) {
        if newState.isSuccess {
            triggerSuccessAnimation()
        } else if newState.isFailed {
            triggerFailureAnimation()
        } else if newState.isScanning {
            triggerScanningAnimation()
        } else {
            triggerIdleAnimation()
        }
    }

    private func triggerIdleAnimation() {
        withAnimation(.easeOut(duration: 0.2)) {
            phase = .idle
            rotationAngle = 0
            checkmarkProgress = 0
            successBounce = 1.0
        }
        startBreathingPulse()
    }

    private func triggerScanningAnimation() {
        // First show the system faceid icon briefly if coming from idle
        if phase == .idle {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) {
                withAnimation(.easeInOut(duration: 0.28)) {
                    phase = .scanning
                }
                startContinuousRotation()
            }
        } else {
            withAnimation(.easeInOut(duration: 0.28)) {
                phase = .scanning
            }
            startContinuousRotation()
        }
    }

    private func startContinuousRotation() {
        rotationAngle = 0
        withAnimation(.linear(duration: 2.2).repeatForever(autoreverses: false)) {
            rotationAngle = 360
        }
    }

    private func triggerSuccessAnimation() {
        // Morph from 3D scanning sphere to circle + checkmark
        withAnimation(.easeInOut(duration: 0.24)) {
            phase = .success
            rotationAngle = 0
        }

        // Draw checkmark path with spring bounce
        withAnimation(.spring(response: 0.38, dampingFraction: 0.68).delay(0.06)) {
            checkmarkProgress = 1.0
            successBounce = 1.08
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.26) {
            withAnimation(.easeOut(duration: 0.18)) {
                successBounce = 1.0
            }
        }
    }

    private func triggerFailureAnimation() {
        withAnimation(.easeInOut(duration: 0.2)) {
            phase = .failed
            rotationAngle = 0
            checkmarkProgress = 0
        }

        // Horizontal shake
        let offsets: [CGFloat] = [-8, 8, -6, 6, -3, 3, 0]
        for (index, offset) in offsets.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(index) * 0.055) {
                withAnimation(.easeInOut(duration: 0.055)) {
                    self.shakeOffset = offset
                }
            }
        }
    }

    private func startBreathingPulse() {
        pulseScale = 0.95
        pulseOpacity = 0.85
        withAnimation(.easeInOut(duration: 0.85).repeatForever(autoreverses: true)) {
            pulseScale = 1.04
            pulseOpacity = 1.0
        }
    }
}

// MARK: - Face ID Checkmark Geometry

struct FaceIDCheckmarkShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width
        let h = rect.height

        // Vertex points matching Apple's circular checkmark glyph
        path.move(to: CGPoint(x: w * 0.315, y: h * 0.515))
        path.addLine(to: CGPoint(x: w * 0.455, y: h * 0.655))
        path.addLine(to: CGPoint(x: w * 0.705, y: h * 0.365))
        return path
    }
}
