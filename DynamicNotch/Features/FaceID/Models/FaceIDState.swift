//
//  FaceIDState.swift
//  DynamicNotch
//

import Foundation

enum FaceIDState: Equatable {
    case idle
    case searching
    case scanning(progress: Double)
    case success
    case failed(reason: String)

    var isScanning: Bool {
        switch self {
        case .searching, .scanning:
            return true
        default:
            return false
        }
    }

    var isSuccess: Bool {
        if case .success = self { return true }
        return false
    }

    var isFailed: Bool {
        if case .failed = self { return true }
        return false
    }

    var statusText: String {
        switch self {
        case .idle:
            return "Face ID"
        case .searching:
            return "Searching for Face..."
        case .scanning(let progress):
            return "Scanning Face (\(Int(progress * 100))%)..."
        case .success:
            return "Face ID Verified"
        case .failed(let reason):
            return reason
        }
    }
}
