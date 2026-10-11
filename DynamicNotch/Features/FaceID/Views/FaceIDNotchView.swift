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
            return .red
        default:
            return .green
        }
    }

    var body: some View {
        VStack {
            Spacer()

            FaceIDPureAnimationView(
                state: service.state,
                color: headlineColor,
                size: 84
            )

            Spacer()
        }
    }
}
