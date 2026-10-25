//
//  FaceIDPresentationStyle.swift
//  DynamicNotch
//

import SwiftUI

enum FaceIDPresentationStyle: String, CaseIterable, Identifiable {
    case expanded = "expanded"
    case compact = "compact"
    
    var id: String { rawValue }
    
    var title: LocalizedStringKey {
        switch self {
        case .expanded:
            return "settings.faceid.style.expanded"
        case .compact:
            return "settings.faceid.style.compact"
        }
    }
    
    var systemImage: String {
        switch self {
        case .expanded:
            return "rectangle.expand.vertical"
        case .compact:
            return "lock.circle.fill"
        }
    }
}
