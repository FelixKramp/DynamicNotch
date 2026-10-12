//
//  FaceIDEnrollmentNotchView.swift
//  DynamicNotch
//

internal import AppKit
@preconcurrency import AVFoundation
import SwiftUI

struct FaceIDEnrollmentNotchView: View {
    let step: FaceIDEnrollmentStep
    let notchViewModel: NotchViewModel
    
    @ObservedObject var settings: FaceIDSettingsStore
    @ObservedObject var cameraService: FaceIDEnrollmentCameraService
    @Environment(\.isNotchlessScreen) private var isNotchlessScreen
    
    var body: some View {
        VStack {
            Spacer()
            stepContent
        }
    }
    
    @ViewBuilder
    private var stepContent: some View {
        switch step {
        case .intro:
            introStepView
                .padding(.horizontal, isNotchlessScreen ? 12 : 40)
                .padding(.bottom, isNotchlessScreen ? 10 : 10)
        case .camera:
            cameraStepView
                .padding(.horizontal, isNotchlessScreen ? 15 : 38)
                .padding(.bottom, isNotchlessScreen ? 15 : 10)
        case .success:
            successStepView
                .padding(.horizontal, isNotchlessScreen ? 20 : 36)
                .padding(.bottom, isNotchlessScreen ? 20 : 10)
        }
    }
    
    private var introStepView: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "faceid")
                    .font(.system(size: 50, weight: .medium))
                    .foregroundStyle(.green)
                
                VStack(alignment: .leading, spacing: 5) {
                    Text(verbatim: "Set Up Face ID")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    
                    Text(verbatim: "Position your face in the camera frame and move your head to scan.")
                        .foregroundColor(.gray.opacity(0.6))
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(2)
                }
            }
            
            HStack {
                Button(action: {
                    cameraService.stopEnrollment()
                    notchViewModel.hideTemporaryNotification()
                }) {
                    Text(verbatim: "Exit")
                        .fontWeight(.medium)
                        .foregroundStyle(.red)
                }
                .buttonStyle(PrimaryButtonStyle(height: 35, backgroundColor: .red.opacity(0.25)))
                
                Spacer()
                
                Button(action: {
                    cameraService.startEnrollment()
                    notchViewModel.send(
                        .showTemporaryNotification(
                            FaceIDEnrollmentNotchContent(
                                step: .camera,
                                settings: settings,
                                notchViewModel: notchViewModel,
                                cameraService: cameraService
                            ),
                            duration: 180.0
                        )
                    )
                }) {
                    Text(verbatim: "Continue")
                        .fontWeight(.medium)
                        .foregroundStyle(.blue)
                }
                .buttonStyle(PrimaryButtonStyle(height: 35, backgroundColor: .blue.opacity(0.25)))
            }
        }
    }
    
    private var cameraStepView: some View {
        let isScanning = cameraService.isFaceInFrame || cameraService.enrollmentProgress > 0
        return ZStack {
            if isScanning && !cameraService.isCompleted {
                FaceIDNotchTickMarksView(
                    progress: cameraService.enrollmentProgress,
                    isCompleted: cameraService.isCompleted,
                    radius: 105,
                    tickCount: 36,
                    tickLength: 12,
                    tickWidth: 3
                )
                .transition(.opacity)
            }
            
            ZStack {
                RoundedRectangle(cornerRadius: isScanning ? 100 : 30)
                    .fill(Color.black)
                    .frame(width: isScanning ? 180 : nil, height: isScanning ? 180 : 220)
                
                switch cameraService.cameraState {
                case .running:
                    NotchFaceCameraPreviewRepresentable(previewLayer: cameraService.previewLayer)
                        .scaleEffect(x: -1, y: 1)
                        .clipShape(RoundedRectangle(cornerRadius: isScanning ? 100 : 30))
                        .frame(width: isScanning ? 180 : nil, height: isScanning ? 180 : 220)
                    
                case .starting:
                    ProgressView()
                        .tint(.white)
                    
                case .permissionDenied:
                    VStack(spacing: 4) {
                        Image(systemName: "camera.fill.badge.ellipsis")
                            .font(.system(size: 22))
                            .foregroundStyle(.orange)
                        Text(verbatim: "No Camera Access")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    
                case .unavailable, .simulated, .uninitialized:
                    EmptyView()
                }
                
                if cameraService.isCompleted {
                    RoundedRectangle(cornerRadius: isScanning ? 100 : 30)
                        .stroke(Color.green, lineWidth: 1.5)
                        .frame(width: isScanning ? 180 : nil, height: isScanning ? 180 : 220)
                        .transition(.opacity)
                }
            }
            .animation(.spring(response: 0.5, dampingFraction: 0.8), value: isScanning)
            .animation(.easeInOut(duration: 0.25), value: cameraService.isCompleted)
        }
        .frame(height: isScanning ? 180 : 220)
        .padding(.bottom, isScanning ? 25 : 0)
        .onChange(of: cameraService.isCompleted) { _, isCompleted in
            if isCompleted {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    notchViewModel.send(
                        .showTemporaryNotification(
                            FaceIDEnrollmentNotchContent(
                                step: .success,
                                settings: settings,
                                notchViewModel: notchViewModel,
                                cameraService: cameraService
                            ),
                            duration: 3.0
                        )
                    )
                }
            }
        }
    }
    
    private var successStepView: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 50, weight: .medium))
                .foregroundStyle(.green)
            
            VStack(alignment: .leading, spacing: 5) {
                Text(verbatim: "Face ID is Ready")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                
                Text(verbatim: "You can now use Face ID to quickly unlock your Mac.")
                    .foregroundColor(.gray.opacity(0.6))
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(2)
            }
            Spacer()
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 8.0) {
                settings.enrollFace()
                settings.isFaceIDEnabled = true
                cameraService.stopEnrollment()
                notchViewModel.hideTemporaryNotification()
            }
        }
    }
}

struct FaceIDNotchTickMarksView: View {
    let progress: Double
    let isCompleted: Bool
    
    var radius: CGFloat = 56
    var tickCount: Int = 36
    var tickLength: CGFloat = 8
    var tickWidth: CGFloat = 2.8
    
    var body: some View {
        ZStack {
            ForEach(0..<tickCount, id: \.self) { index in
                let fraction = Double(index) / Double(tickCount)
                let isFilled = fraction <= progress
                
                RoundedRectangle(cornerRadius: 30)
                    .fill(isFilled ? Color.green : Color.white.opacity(0.2))
                    .frame(width: tickWidth, height: tickLength)
                    .offset(y: -radius)
                    .rotationEffect(.degrees(Double(index) / Double(tickCount) * 360.0))
            }
        }
        .frame(width: (radius + tickLength) * 2, height: (radius + tickLength) * 2)
    }
}

private struct NotchFaceCameraPreviewRepresentable: NSViewRepresentable {
    let previewLayer: AVCaptureVideoPreviewLayer
    
    func makeNSView(context: Context) -> NotchFaceCameraPreviewContainerView {
        NotchFaceCameraPreviewContainerView(previewLayer: previewLayer)
    }
    
    func updateNSView(_ nsView: NotchFaceCameraPreviewContainerView, context: Context) {}
}

private final class NotchFaceCameraPreviewContainerView: NSView {
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
