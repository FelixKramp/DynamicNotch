//
//  FaceIDPureAnimationView.swift
//  DynamicNotch
//
//  A 100% native SwiftUI recreation of Apple's Face ID scanning animation:
//  - Starts with ONLY the authentic Apple SF Symbol `faceid` (pulsing gently while searching)
//  - ONLY when a face is detected and scanning begins, morphs into a 3D rotating spherical wireframe (gyroscope)
//  - Smoothly aligns and transitions into a bounded circle with a dynamically drawn checkmark upon success
//  - Returns to the original `faceid` glyph in red with a horizontal shake upon failure
//  - Fully customizable color
//

import SwiftUI

struct FaceIDPureAnimationView: View {
    let state: FaceIDState
    var color: Color
    var size: CGFloat
    
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
            if phase == .idle || phase == .failed {
                Image(systemName: "faceid")
                    .font(.system(size: size, weight: .light))
                    .foregroundStyle(color)
                    .scaleEffect(phase == .idle ? pulseScale : 1.0)
                    .opacity(phase == .idle ? pulseOpacity : 1.0)
                    .transition(
                        .asymmetric(
                            insertion: .opacity.combined(with: .scale(scale: 0.92)),
                            removal: .opacity.combined(with: .scale(scale: 1.08))
                        )
                    )
            }
            
            if phase == .scanning {
                gyroscopeScanningView
                    .transition(
                        .asymmetric(
                            insertion: .opacity.combined(with: .scale(scale: 0.90)),
                            removal: .opacity.combined(with: .scale(scale: 1.06))
                        )
                    )
            }
            
            if phase == .success {
                successCheckmarkView
                    .transition(
                        .asymmetric(
                            insertion: .opacity.combined(with: .scale(scale: 0.92)),
                            removal: .opacity.combined(with: .scale(scale: 0.90))
                        )
                    )
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
    
    private var gyroscopeScanningView: some View {
        ZStack {
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
            
            Circle()
                .stroke(color.opacity(0.32), lineWidth: 2.2)
                .frame(width: size * 0.94, height: size * 0.94)
                .blur(radius: 0.5)
            
            Circle()
                .stroke(color, lineWidth: 4.6)
                .frame(width: size * 0.94, height: size * 0.94)
                .rotation3DEffect(
                    .degrees(rotationAngle),
                    axis: (x: 0.35, y: 1.0, z: 0.15),
                    perspective: 0.55
                )
            
            Circle()
                .stroke(color.opacity(0.85), lineWidth: 4.0)
                .frame(width: size * 0.94, height: size * 0.94)
                .rotation3DEffect(
                    .degrees(rotationAngle + 65),
                    axis: (x: -0.55, y: 0.9, z: -0.25),
                    perspective: 0.55
                )
            
            Circle()
                .stroke(color.opacity(0.60), lineWidth: 3.2)
                .frame(width: size * 0.88, height: size * 0.88)
                .rotation3DEffect(
                    .degrees(rotationAngle * 1.35),
                    axis: (x: 1.0, y: 0.25, z: 0.4),
                    perspective: 0.55
                )
            
            Circle()
                .stroke(color.opacity(0.40), lineWidth: 2.4)
                .frame(width: size * 0.82, height: size * 0.82)
                .rotation3DEffect(
                    .degrees(-rotationAngle * 0.85),
                    axis: (x: 0.6, y: -0.4, z: 0.8),
                    perspective: 0.55
                )
        }
    }
    
    private var successCheckmarkView: some View {
        ZStack {
            Circle()
                .stroke(color, lineWidth: 5.6)
                .frame(width: size * 0.94, height: size * 0.94)
            
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
    
    private func handleStateTransition(to newState: FaceIDState, animated: Bool) {
        switch newState {
        case .idle, .searching:
            if phase != .idle {
                triggerIdleAnimation(animated: animated)
            } else {
                startBreathingPulse()
            }
        case .scanning:
            if phase != .scanning {
                triggerScanningAnimation(animated: animated)
            }
        case .success:
            if phase != .success {
                triggerSuccessAnimation(animated: animated)
            }
        case .failed:
            if phase != .failed {
                triggerFailureAnimation(animated: animated)
            }
        }
    }
    
    private func triggerIdleAnimation(animated: Bool) {
        if animated {
            withAnimation(.easeInOut(duration: 0.5)) {
                phase = .idle
                rotationAngle = 0
                checkmarkProgress = 0
                successBounce = 1.0
            }
        } else {
            phase = .idle
            rotationAngle = 0
            checkmarkProgress = 0
            successBounce = 1.0
        }
        startBreathingPulse()
    }
    
    private func triggerScanningAnimation(animated: Bool) {
        pulseScale = 1.0
        pulseOpacity = 1.0
        
        if animated {
            withAnimation(.spring(response: 0.36, dampingFraction: 0.78)) {
                phase = .scanning
            }
        } else {
            phase = .scanning
        }
        startContinuousRotation()
    }
    
    private func startContinuousRotation() {
        rotationAngle = 0
        withAnimation(.linear(duration: 2.2).repeatForever(autoreverses: false)) {
            rotationAngle = 360
        }
    }
    
    private func triggerSuccessAnimation(animated: Bool) {
        if animated {
            withAnimation(.easeInOut(duration: 0.24)) {
                phase = .success
                rotationAngle = 0
            }
            withAnimation(.spring(response: 0.38, dampingFraction: 0.68).delay(0.06)) {
                checkmarkProgress = 1.0
                successBounce = 1.08
            }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.26) {
                withAnimation(.easeOut(duration: 0.18)) {
                    successBounce = 1.0
                }
            }
        } else {
            phase = .success
            rotationAngle = 0
            checkmarkProgress = 1.0
            successBounce = 1.0
        }
    }
    
    private func triggerFailureAnimation(animated: Bool) {
        pulseScale = 1.0
        pulseOpacity = 1.0
        
        if animated {
            withAnimation(.easeInOut(duration: 0.2)) {
                phase = .failed
                rotationAngle = 0
                checkmarkProgress = 0
            }
            let offsets: [CGFloat] = [-8, 8, -6, 6, -3, 3, 0]
            for (index, offset) in offsets.enumerated() {
                DispatchQueue.main.asyncAfter(deadline: .now() + Double(index) * 0.055) {
                    withAnimation(.easeInOut(duration: 0.055)) {
                        self.shakeOffset = offset
                    }
                }
            }
        } else {
            phase = .failed
            rotationAngle = 0
            checkmarkProgress = 0
        }
    }
    
    private func startBreathingPulse() {
        pulseScale = 0.93
        pulseOpacity = 0.5
        withAnimation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true)) {
            pulseScale = 1.0
            pulseOpacity = 1.0
        }
    }
}
