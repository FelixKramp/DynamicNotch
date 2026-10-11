//
//  FaceIDEnrollmentSheetView.swift
//  DynamicNotch
//

import SwiftUI
import AVFoundation
internal import AppKit

struct FaceIDEnrollmentSheetView: View {
    @ObservedObject var settings: FaceIDSettingsStore
    var service: FaceIDService?

    @Environment(\.dismiss) private var dismiss
    @StateObject private var cameraService = FaceIDEnrollmentCameraService()

    @State private var pulseGlow = false

    var body: some View {
        VStack(spacing: 20) {
            // Header
            VStack(spacing: 6) {
                Image(systemName: "faceid")
                    .font(.system(size: 32, weight: .semibold))
                    .foregroundStyle(headerIconColor)

                Text("Настройка Face ID")
                    .font(.system(size: 21, weight: .bold, design: .rounded))

                Text(cameraService.instructionText)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(height: 38)
            }
            .padding(.top, 14)

            // Apple-style Circular Camera Guide with 48 Ticks
            ZStack {
                // Outer 48 Radial Tick Marks
                FaceIDTickMarksView(
                    progress: cameraService.enrollmentProgress,
                    isCompleted: cameraService.isCompleted
                )

                // Circular Camera Viewport
                ZStack {
                    // Dark background placeholder
                    Circle()
                        .fill(Color.black.opacity(0.85))

                    // Live Camera Stream or Simulated Preview
                    switch cameraService.cameraState {
                    case .running:
                        FaceCameraPreviewRepresentable(previewLayer: cameraService.previewLayer)
                            .scaleEffect(x: -1, y: 1) // Mirror front camera like a selfie mirror
                            .clipShape(Circle())

                    case .starting:
                        ProgressView()
                            .progressViewStyle(.circular)
                            .tint(.white)

                    case .permissionDenied:
                        VStack(spacing: 8) {
                            Image(systemName: "camera.fill.badge.ellipsis")
                                .font(.system(size: 32))
                                .foregroundStyle(.orange)
                            Text("Доступ к камере закрыт")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.secondary)
                        }

                    case .unavailable(let reason):
                        VStack(spacing: 8) {
                            Image(systemName: "video.slash.fill")
                                .font(.system(size: 32))
                                .foregroundStyle(.secondary)
                            Text(reason)
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 16)
                        }

                    case .simulated:
                        // Visual demo avatar
                        ZStack {
                            Circle()
                                .fill(LinearGradient(colors: [.indigo.opacity(0.3), .cyan.opacity(0.2)], startPoint: .topLeading, endPoint: .bottomTrailing))

                            Image(systemName: "person.crop.circle.fill")
                                .font(.system(size: 96))
                                .foregroundStyle(.white.opacity(0.4))
                        }

                    case .uninitialized:
                        EmptyView()
                    }

                    // Biometric Reticle / Corner Brackets
                    if !cameraService.isCompleted {
                        FaceReticleOverlayView(isFaceInFrame: cameraService.isFaceInFrame)
                    } else {
                        // Completion Celebration Overlay
                        ZStack {
                            Circle()
                                .fill(Color.black.opacity(0.45))

                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 64, weight: .bold))
                                .foregroundStyle(.green)
                                .scaleEffect(pulseGlow ? 1.05 : 0.95)
                                .shadow(color: .green.opacity(0.8), radius: 12)
                        }
                        .transition(.scale.combined(with: .opacity))
                    }
                }
                .frame(width: 200, height: 200)
                .clipShape(Circle())
                .overlay(
                    Circle()
                        .stroke(
                            cameraService.isCompleted
                                ? Color.green.opacity(0.8)
                                : (cameraService.isFaceInFrame ? Color.cyan.opacity(0.6) : Color.white.opacity(0.2)),
                            lineWidth: 2
                        )
                )
            }
            .frame(width: 260, height: 260)
            .padding(.vertical, 4)

            // Progress percentage & hints
            if cameraService.isCompleted {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundStyle(.green)
                    Text("Лицо успешно зарегистрировано")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.green)
                }
            } else {
                Text("\(Int(cameraService.enrollmentProgress * 100))%")
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .foregroundStyle(cameraService.isFaceInFrame ? .cyan : .secondary)
            }

            // Buttons / Actions
            HStack(spacing: 14) {
                Button("Отмена") {
                    cameraService.stopEnrollment()
                    dismiss()
                }
                .buttonStyle(.bordered)
                .keyboardShortcut(.cancelAction)

                if cameraService.isCompleted {
                    Button("Готово") {
                        settings.enrollFace()
                        cameraService.stopEnrollment()
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                    .keyboardShortcut(.defaultAction)
                } else if case .permissionDenied = cameraService.cameraState {
                    Button("Настройки приватности") {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                } else if case .unavailable = cameraService.cameraState {
                    Button("Демо-сканирование") {
                        cameraService.startSimulatedFlow()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(.bottom, 12)
        }
        .padding(24)
        .frame(width: 400)
        .onAppear {
            cameraService.startEnrollment()
            withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
                pulseGlow = true
            }
        }
        .onDisappear {
            cameraService.stopEnrollment()
        }
        .onChange(of: cameraService.isCompleted) { _, completed in
            if completed {
                settings.enrollFace()
            }
        }
    }

    private var headerIconColor: Color {
        if cameraService.isCompleted {
            return .green
        } else if cameraService.isFaceInFrame {
            return .cyan
        } else {
            return .secondary
        }
    }
}

// MARK: - 48-Tick Radial Progress Ring (Apple Face ID Style)

private struct FaceIDTickMarksView: View {
    let progress: Double
    let isCompleted: Bool

    private let tickCount: Int = 48
    private let radius: CGFloat = 118
    private let tickLength: CGFloat = 11
    private let tickWidth: CGFloat = 3.2

    var body: some View {
        ZStack {
            ForEach(0..<tickCount, id: \.self) { index in
                let fraction = Double(index) / Double(tickCount)
                let isFilled = fraction <= progress

                Capsule()
                    .fill(
                        isFilled
                            ? (isCompleted ? Color.green : Color.cyan)
                            : Color.white.opacity(0.18)
                    )
                    .frame(width: tickWidth, height: tickLength)
                    .shadow(
                        color: isFilled
                            ? (isCompleted ? Color.green.opacity(0.8) : Color.cyan.opacity(0.8))
                            : .clear,
                        radius: isFilled ? 4 : 0
                    )
                    .offset(y: -radius)
                    .rotationEffect(.degrees(Double(index) / Double(tickCount) * 360.0))
            }
        }
        .frame(width: (radius + tickLength) * 2, height: (radius + tickLength) * 2)
    }
}

// MARK: - Biometric Corner Reticles

private struct FaceReticleOverlayView: View {
    let isFaceInFrame: Bool

    var body: some View {
        ZStack {
            let color = isFaceInFrame ? Color.cyan : Color.white.opacity(0.4)
            let lineWidth: CGFloat = 2.5
            let cornerSize: CGFloat = 16

            VStack {
                HStack {
                    // Top-Left
                    Path { path in
                        path.move(to: CGPoint(x: 0, y: cornerSize))
                        path.addLine(to: CGPoint(x: 0, y: 0))
                        path.addLine(to: CGPoint(x: cornerSize, y: 0))
                    }
                    .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .frame(width: cornerSize, height: cornerSize)

                    Spacer()

                    // Top-Right
                    Path { path in
                        path.move(to: CGPoint(x: 0, y: 0))
                        path.addLine(to: CGPoint(x: cornerSize, y: 0))
                        path.addLine(to: CGPoint(x: cornerSize, y: cornerSize))
                    }
                    .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .frame(width: cornerSize, height: cornerSize)
                }

                Spacer()

                HStack {
                    // Bottom-Left
                    Path { path in
                        path.move(to: CGPoint(x: 0, y: 0))
                        path.addLine(to: CGPoint(x: 0, y: cornerSize))
                        path.addLine(to: CGPoint(x: cornerSize, y: cornerSize))
                    }
                    .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .frame(width: cornerSize, height: cornerSize)

                    Spacer()

                    // Bottom-Right
                    Path { path in
                        path.move(to: CGPoint(x: cornerSize, y: 0))
                        path.addLine(to: CGPoint(x: cornerSize, y: cornerSize))
                        path.addLine(to: CGPoint(x: 0, y: cornerSize))
                    }
                    .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .frame(width: cornerSize, height: cornerSize)
                }
            }
            .frame(width: 120, height: 135)
            .animation(.easeInOut(duration: 0.25), value: isFaceInFrame)
        }
    }
}

// MARK: - Camera Preview NSViewRepresentable

private struct FaceCameraPreviewRepresentable: NSViewRepresentable {
    let previewLayer: AVCaptureVideoPreviewLayer

    func makeNSView(context: Context) -> FaceCameraPreviewContainerView {
        FaceCameraPreviewContainerView(previewLayer: previewLayer)
    }

    func updateNSView(_ nsView: FaceCameraPreviewContainerView, context: Context) {}
}

private final class FaceCameraPreviewContainerView: NSView {
    private weak var previewLayer: AVCaptureVideoPreviewLayer?

    init(previewLayer: AVCaptureVideoPreviewLayer) {
        self.previewLayer = previewLayer
        super.init(frame: .zero)
        self.wantsLayer = true
        self.layer?.masksToBounds = true
        self.layer?.addSublayer(previewLayer)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        previewLayer?.frame = bounds
    }
}
