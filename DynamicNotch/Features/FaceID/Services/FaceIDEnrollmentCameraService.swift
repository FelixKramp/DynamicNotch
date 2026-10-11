//
//  FaceIDEnrollmentCameraService.swift
//  DynamicNotch
//

internal import AppKit
@preconcurrency import AVFoundation
import Combine
import SwiftUI
@preconcurrency internal import Vision

enum FaceCameraState: Equatable {
    case uninitialized
    case starting
    case running
    case permissionDenied
    case unavailable(String)
    case simulated
}

@MainActor
final class FaceIDEnrollmentCameraService: NSObject, ObservableObject {
    @Published var cameraState: FaceCameraState = .uninitialized
    @Published var isFaceInFrame: Bool = false
    @Published var enrollmentProgress: Double = 0.0
    @Published var instructionText: String = "Position your face within the frame"
    @Published var isCompleted: Bool = false
    @Published var simulatedMode: Bool = false

    private func updateInstruction(_ text: String) {
        self.instructionText = text
    }

    let previewLayer = AVCaptureVideoPreviewLayer()

    private let session = AVCaptureSession()
    private let captureQueue = DispatchQueue(label: "com.dynamicnotch.faceid.captureQueue", qos: .userInitiated)
    nonisolated(unsafe) private var isConfigured = false
    private var simulatedTimer: AnyCancellable?
    private var lastSuccessfulObservationTime: Date = .distantPast

    override init() {
        super.init()
        previewLayer.session = session
        previewLayer.videoGravity = .resizeAspectFill
    }

    deinit {
        simulatedTimer?.cancel()
        previewLayer.session = nil
        let captureSession = session
        captureQueue.async {
            if captureSession.isRunning {
                captureSession.stopRunning()
            }
        }
    }

    func startEnrollment() {
        isCompleted = false
        enrollmentProgress = 0.0
        updateInstruction("Position your face within the frame")
        isFaceInFrame = false

        checkPermissionsAndStart()
    }

    func stopEnrollment() {
        simulatedTimer?.cancel()
        simulatedTimer = nil
        stopCameraSession()
    }

    private func checkPermissionsAndStart() {
        guard !AppEnvironment.isRunningTests else {
            cameraState = .unavailable("Test environment")
            return
        }

        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            setupAndStartCamera()
        case .notDetermined:
            cameraState = .starting
            updateInstruction("Requesting camera access...")
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    if granted {
                        self?.setupAndStartCamera()
                    } else {
                        self?.cameraState = .permissionDenied
                        self?.updateInstruction("Camera access denied")
                    }
                }
            }
        case .denied, .restricted:
            cameraState = .permissionDenied
            updateInstruction("Allow camera access in System Settings")
        @unknown default:
            cameraState = .unavailable("Unknown camera status")
        }
    }

    private func setupAndStartCamera() {
        let captureSession = session
        captureQueue.async { [weak self] in
            guard let self else { return }

            if !self.isConfigured {
                captureSession.beginConfiguration()
                captureSession.sessionPreset = .high

                for input in captureSession.inputs {
                    captureSession.removeInput(input)
                }
                for output in captureSession.outputs {
                    captureSession.removeOutput(output)
                }

                guard let device = AVCaptureDevice.default(for: .video) else {
                    captureSession.commitConfiguration()
                    DispatchQueue.main.async {
                        self.cameraState = .unavailable("Camera not found")
                        self.updateInstruction("Camera not found")
                    }
                    return
                }

                do {
                    let input = try AVCaptureDeviceInput(device: device)
                    if captureSession.canAddInput(input) {
                        captureSession.addInput(input)
                    }

                    let videoOutput = AVCaptureVideoDataOutput()
                    videoOutput.alwaysDiscardsLateVideoFrames = true
                    videoOutput.videoSettings = [
                        kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)
                    ]
                    videoOutput.setSampleBufferDelegate(self, queue: self.captureQueue)

                    if captureSession.canAddOutput(videoOutput) {
                        captureSession.addOutput(videoOutput)
                    }

                    captureSession.commitConfiguration()
                    self.isConfigured = true
                } catch {
                    captureSession.commitConfiguration()
                    DispatchQueue.main.async {
                        self.cameraState = .unavailable(error.localizedDescription)
                    }
                    return
                }
            }

            if !captureSession.isRunning {
                captureSession.startRunning()
            }

            DispatchQueue.main.async {
                self.cameraState = .running
                self.updateInstruction("Position your face and look at the camera")
            }
        }
    }

    func stopCameraSession() {
        let captureSession = session
        captureQueue.async {
            if captureSession.isRunning {
                captureSession.stopRunning()
            }
        }
    }

    func startSimulatedFlow() {
        simulatedMode = true
        cameraState = .simulated
        enrollmentProgress = 0.0
        isCompleted = false
        isFaceInFrame = true

        simulatedTimer?.cancel()
        simulatedTimer = Timer.publish(every: 0.1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self, !self.isCompleted else { return }

                self.enrollmentProgress += 0.025
                if self.enrollmentProgress < 0.3 {
                    self.updateInstruction("Position your face within the frame")
                } else if self.enrollmentProgress < 0.6 {
                    self.updateInstruction("Slowly turn your head to the right")
                } else if self.enrollmentProgress < 0.9 {
                    self.updateInstruction("Now turn your head to the left")
                } else if self.enrollmentProgress < 1.0 {
                    self.updateInstruction("Finishing scan...")
                } else {
                    self.enrollmentProgress = 1.0
                    self.isCompleted = true
                    self.updateInstruction("Face ID successfully set up!")
                    self.simulatedTimer?.cancel()
                }
            }
    }

    private func handleDetectedFace(_ face: VNFaceObservation) {
        guard !isCompleted else { return }

        let box = face.boundingBox
        let isCentered = (0.15...0.85).contains(box.midX) && (0.15...0.85).contains(box.midY)
        let isReasonableSize = box.width >= 0.14 && box.width <= 0.88

        if !isCentered || !isReasonableSize {
            isFaceInFrame = false
            if box.width < 0.14 {
                updateInstruction("Move closer to the screen")
            } else {
                updateInstruction("Center your face in the frame")
            }
            return
        }

        isFaceInFrame = true
        lastSuccessfulObservationTime = Date()

        enrollmentProgress = min(1.0, enrollmentProgress + 0.025)

        if enrollmentProgress < 0.30 {
            updateInstruction("Great! Hold your face in the frame")
        } else if enrollmentProgress < 0.60 {
            updateInstruction("Slightly turn your head to the right")
        } else if enrollmentProgress < 0.85 {
            updateInstruction("Now slightly turn your head to the left")
        } else if enrollmentProgress < 1.0 {
            updateInstruction("Finishing scan...")
        } else {
            isCompleted = true
            updateInstruction("Face ID successfully set up!")
            stopCameraSession()
        }
    }

    private func handleNoFace() {
        guard !isCompleted else { return }
        if Date().timeIntervalSince(lastSuccessfulObservationTime) > 0.4 {
            isFaceInFrame = false
            updateInstruction("Position your face within the frame")
        }
    }
}

extension FaceIDEnrollmentCameraService: AVCaptureVideoDataOutputSampleBufferDelegate {
    nonisolated func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        // Process synchronously on captureQueue while pixelBuffer is guaranteed valid
        let request = VNDetectFaceLandmarksRequest()
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up, options: [:])

        do {
            try handler.perform([request])
            let face = request.results?.first

            DispatchQueue.main.async { [weak self] in
                guard let self, !self.isCompleted else { return }
                if let face {
                    self.handleDetectedFace(face)
                } else {
                    self.handleNoFace()
                }
            }
        } catch {
            DispatchQueue.main.async { [weak self] in
                self?.handleNoFace()
            }
        }
    }
}
