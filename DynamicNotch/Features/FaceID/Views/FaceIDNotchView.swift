//
//  FaceIDNotchView.swift
//  DynamicNotch
//

import SwiftUI

struct FaceIDNotchView: View {
    @Environment(\.isNotchlessScreen) private var isNotchlessScreen
    @ObservedObject var service: FaceIDService = .shared
    
    private var headlineColor: Color {
        switch service.state {
        case .searching, .scanning, .success:
            return .green
        case .failed:
            return .white.opacity(0.2)
        default:
            return .green
        }
    }
    
    var body: some View {
        VStack {
            Spacer()
            FaceIDPureAnimationView(state: service.state, color: headlineColor, size: 85)
            Spacer()
        }
    }
}
