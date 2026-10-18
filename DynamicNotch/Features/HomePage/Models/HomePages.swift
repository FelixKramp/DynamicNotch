//
//  HomePages.swift
//  DynamicNotch
//
//  Created by Евгений Петрукович on 9/27/26.
//

import SwiftUI

enum HomePages: String, CaseIterable, Hashable, Codable, Identifiable {
    case camera
    case localTimer
    
    var id: String { rawValue }
    
    var title: LocalizedStringKey {
        switch self {
        case .camera: return "settings.homePage.pages.camera.title"
        case .localTimer: return "settings.homePage.pages.timer.title"
        }
    }
    
    var subtitle: LocalizedStringKey {
        switch self {
        case .camera: return "settings.homePage.pages.camera.subtitle"
        case .localTimer: return "settings.homePage.pages.timer.subtitle"
        }
    }
    
    var icon: String {
        switch self {
        case .camera: return "camera.fill"
        case .localTimer: return "timer"
        }
    }
    
    var tint: Color {
        switch self {
        case .camera: return .gray
        case .localTimer: return .orange
        }
    }
    
    var iconTint: Color {
        switch self {
        case .camera: return .black
        case .localTimer: return .white
        }
    }
}
