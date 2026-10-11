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

    var isSearching: Bool {
        if case .searching = self { return true }
        return false
    }

    var isScanning: Bool {
        if case .scanning = self { return true }
        return false
    }

    var isActivelyEvaluating: Bool {
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
}
