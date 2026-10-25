//
//  FaceAttentionEvaluator.swift
//  DynamicNotch
//

import Foundation
@preconcurrency internal import Vision

enum FaceAttentionEvaluator {
    /// Checks whether the user is facing directly forward towards the camera.
    /// yaw: rotation around vertical axis (left/right). Positive is right/left depending on coordinate frame.
    /// pitch: tilt up/down.
    /// roll: head tilt sideways.
    static func isFacingCamera(face: VNFaceObservation, maxAngleRadians: Double = 0.22) -> Bool {
        if let yaw = face.yaw?.doubleValue {
            if abs(yaw) > maxAngleRadians {
                return false
            }
        }
        if let pitch = face.pitch?.doubleValue {
            if abs(pitch) > maxAngleRadians {
                return false
            }
        }
        if let roll = face.roll?.doubleValue {
            if abs(roll) > 0.35 {
                return false
            }
        }
        return true
    }

    /// Evaluates whether both eyes are open using the Eye Openness Ratio (EAR).
    /// Returns true if landmarks are available and both eyes exceed the open ratio threshold.
    static func areEyesOpen(face: VNFaceObservation, threshold: Double = 0.16) -> Bool {
        guard let landmarks = face.landmarks,
              let leftEye = landmarks.leftEye,
              let rightEye = landmarks.rightEye else {
            return false
        }

        let leftRatio = eyeOpennessRatio(eye: leftEye)
        let rightRatio = eyeOpennessRatio(eye: rightEye)

        guard let leftRatio, let rightRatio else {
            return false
        }

        return leftRatio >= threshold && rightRatio >= threshold
    }

    /// Evaluates whether the user's pupils/gaze are looking relatively straight ahead at the camera.
    static func isGazeDirect(face: VNFaceObservation, maxOffsetRatio: Double = 0.28) -> Bool {
        guard let landmarks = face.landmarks,
              let leftEye = landmarks.leftEye,
              let rightEye = landmarks.rightEye else {
            return true // Fallback to true if eye contour landmarks aren't detailed enough
        }

        let leftPupil = landmarks.leftPupil?.normalizedPoints.first
        let rightPupil = landmarks.rightPupil?.normalizedPoints.first

        if let leftPupil {
            if !isPupilCentered(pupil: leftPupil, eye: leftEye, maxOffsetRatio: maxOffsetRatio) {
                return false
            }
        }
        if let rightPupil {
            if !isPupilCentered(pupil: rightPupil, eye: rightEye, maxOffsetRatio: maxOffsetRatio) {
                return false
            }
        }

        return true
    }

    /// Returns yaw angle in radians if available.
    static func getYaw(face: VNFaceObservation) -> Double? {
        face.yaw?.doubleValue
    }

    // MARK: - Private Helpers

    private static func eyeOpennessRatio(eye: VNFaceLandmarkRegion2D) -> Double? {
        let points = eye.normalizedPoints
        guard points.count >= 4 else { return nil }

        var minX: Double = .greatestFiniteMagnitude
        var maxX: Double = -.greatestFiniteMagnitude
        var minY: Double = .greatestFiniteMagnitude
        var maxY: Double = -.greatestFiniteMagnitude

        for pt in points {
            let x = Double(pt.x)
            let y = Double(pt.y)
            if x < minX { minX = x }
            if x > maxX { maxX = x }
            if y < minY { minY = y }
            if y > maxY { maxY = y }
        }

        let width = maxX - minX
        let height = maxY - minY

        guard width > 0.001 else { return nil }
        return height / width
    }

    private static func isPupilCentered(pupil: CGPoint, eye: VNFaceLandmarkRegion2D, maxOffsetRatio: Double) -> Bool {
        let points = eye.normalizedPoints
        guard !points.isEmpty else { return true }

        var minX: Double = .greatestFiniteMagnitude
        var maxX: Double = -.greatestFiniteMagnitude

        for pt in points {
            let x = Double(pt.x)
            if x < minX { minX = x }
            if x > maxX { maxX = x }
        }

        let width = maxX - minX
        guard width > 0.001 else { return true }

        let centerX = (minX + maxX) / 2.0
        let offset = abs(Double(pupil.x) - centerX) / width
        return offset <= maxOffsetRatio
    }
}
