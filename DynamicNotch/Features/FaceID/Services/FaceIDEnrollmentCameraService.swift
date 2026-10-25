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
    @Published var instructionText: String = L10n.app("faceid.camera.instruction.placeFace", fallback: "Position your face within the frame")
    @Published var isCompleted: Bool = false
    @Published var simulatedMode: Bool = false

    private func updateInstruction(_ key: String, fallback: String) {
        self.instructionText = L10n.app(key, fallback: fallback)
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
        updateInstruction("faceid.camera.instruction.placeFace", fallback: "Position your face within the frame")
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
            updateInstruction("faceid.camera.error.requesting", fallback: "Requesting camera access...")
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    if granted {
                        self?.setupAndStartCamera()
                    } else {
                        self?.cameraState = .permissionDenied
                        self?.updateInstruction("faceid.camera.error.denied", fallback: "Camera access denied")
                    }
                }
            }
        case .denied, .restricted:
            cameraState = .permissionDenied
            updateInstruction("faceid.camera.error.allowInSettings", fallback: "Allow camera access in System Settings")
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
                        self.updateInstruction("faceid.camera.error.notFound", fallback: "Camera not found")
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
                self.updateInstruction("faceid.camera.instruction.lookAtCamera", fallback: "Position your face and look at the camera")
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
                    self.updateInstruction("faceid.camera.instruction.placeFace", fallback: "Position your face within the frame")
                } else if self.enrollmentProgress < 0.6 {
                    self.updateInstruction("faceid.camera.instruction.turnRightSlowly", fallback: "Slowly turn your head to the right")
                } else if self.enrollmentProgress < 0.9 {
                    self.updateInstruction("faceid.camera.instruction.turnLeft", fallback: "Now turn your head to the left")
                } else if self.enrollmentProgress < 1.0 {
                    self.updateInstruction("faceid.camera.instruction.finishing", fallback: "Finishing scan...")
                } else {
                    self.enrollmentProgress = 1.0
                    self.isCompleted = true
                    self.updateInstruction("faceid.camera.instruction.completed", fallback: "Face ID successfully set up!")
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
                updateInstruction("faceid.camera.instruction.closer", fallback: "Move closer to the screen")
            } else {
                updateInstruction("faceid.camera.instruction.centerFace", fallback: "Center your face in the frame")
            }
            return
        }

        isFaceInFrame = true
        lastSuccessfulObservationTime = Date()

        let eyesOpen = FaceAttentionEvaluator.areEyesOpen(face: face)
        let yaw = FaceAttentionEvaluator.getYaw(face: face) ?? 0.0

        if enrollmentProgress < 0.40 {
            // Phase 1: Look straight into the camera with open eyes
            let facingStraight = FaceAttentionEvaluator.isFacingCamera(face: face, maxAngleRadians: 0.18)
            let gazeForward = FaceAttentionEvaluator.isGazeDirect(face: face)

            if !eyesOpen || !facingStraight || !gazeForward {
                updateInstruction("faceid.camera.instruction.lookAtCamera", fallback: "Look directly at the camera with eyes open")
                return
            }

            enrollmentProgress = min(0.40, enrollmentProgress + 0.02)
            if enrollmentProgress < 0.40 {
                updateInstruction("faceid.camera.instruction.holdStill", fallback: "Great! Hold your face in the frame")
            } else {
                updateInstruction("faceid.camera.instruction.turnRightSlightly", fallback: "Slightly turn your head to the right")
            }
        } else if enrollmentProgress < 0.70 {
            // Phase 2: Slightly turn head to the right
            if !eyesOpen {
                updateInstruction("faceid.camera.instruction.lookAtCamera", fallback: "Look directly at the camera with eyes open")
                return
            }

            // Yaw indicates turning: positive/negative depending on orientation. Check if turning away from center (|yaw| > 0.10)
            if abs(yaw) >= 0.10 {
                enrollmentProgress = min(0.70, enrollmentProgress + 0.02)
                if enrollmentProgress >= 0.70 {
                    updateInstruction("faceid.camera.instruction.turnLeftSlightly", fallback: "Now slightly turn your head to the left")
                } else {
                    updateInstruction("faceid.camera.instruction.turnRightSlightly", fallback: "Slightly turn your head to the right")
                }
            } else {
                updateInstruction("faceid.camera.instruction.turnRightSlightly", fallback: "Slightly turn your head to the right")
            }
        } else if enrollmentProgress < 0.92 {
            // Phase 3: Slightly turn head to the left
            if !eyesOpen {
                updateInstruction("faceid.camera.instruction.lookAtCamera", fallback: "Look directly at the camera with eyes open")
                return
            }

            if abs(yaw) >= 0.10 {
                enrollmentProgress = min(0.92, enrollmentProgress + 0.02)
                if enrollmentProgress >= 0.92 {
                    updateInstruction("faceid.camera.instruction.finishing", fallback: "Finishing scan...")
                } else {
                    updateInstruction("faceid.camera.instruction.turnLeftSlightly", fallback: "Now slightly turn your head to the left")
                }
            } else {
                updateInstruction("faceid.camera.instruction.turnLeftSlightly", fallback: "Now slightly turn your head to the left")
            }
        } else {
            // Phase 4: Final verification and finish
            let facingStraight = FaceAttentionEvaluator.isFacingCamera(face: face, maxAngleRadians: 0.22)
            if !eyesOpen || !facingStraight {
                updateInstruction("faceid.camera.instruction.lookAtCamera", fallback: "Look directly at the camera with eyes open")
                return
            }

            enrollmentProgress = min(1.0, enrollmentProgress + 0.03)
            if enrollmentProgress >= 1.0 {
                isCompleted = true
                updateInstruction("faceid.camera.instruction.completed", fallback: "Face ID successfully set up!")
                stopCameraSession()
            } else {
                updateInstruction("faceid.camera.instruction.finishing", fallback: "Finishing scan...")
            }
        }
    }

    private func handleNoFace() {
        guard !isCompleted else { return }
        if Date().timeIntervalSince(lastSuccessfulObservationTime) > 0.4 {
            isFaceInFrame = false
            updateInstruction("faceid.camera.instruction.placeFace", fallback: "Position your face within the frame")
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
