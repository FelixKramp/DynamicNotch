//
//  FaceIDNotchView.swift
//  DynamicNotch
//

import SwiftUI

struct FaceIDNotchView: View {
    @Environment(\.isNotchlessScreen) private var isNotchlessScreen
    @ObservedObject var service: FaceIDService = .shared
    
    @State private var pulseOpacity: CGFloat = 1.0
    @State private var pulseScale: CGFloat = 1.0

    var body: some View {
        VStack {
            Spacer()

            Image(systemName: "faceid")
                .foregroundStyle(headlineColor)
                .font(.system(size: 90))
            
            Spacer()
        }
        .onAppear {
            
        }
    }

    private var headlineColor: Color {
        switch service.state {
        case .success:
            return .green
        case .failed:
            return .red
        default:
            return .green
        }
    }
}
