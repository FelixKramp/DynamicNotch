import SwiftUI

enum HudPresentationKind {
    case brightness
    case keyboard
    case volume

    var sharedContentID: String {
        switch self {
        case .brightness, .volume:
            return NotchContentRegistry.HUD.system.id
        case .keyboard:
            return NotchContentRegistry.HUD.keyboard.id
        }
    }

    func title(locale: Locale? = nil) -> String {
        let key: String
        let fallback: String
        switch self {
        case .brightness:
            key = "notch.hud.display"
            fallback = "Display"
        case .keyboard:
            key = "notch.hud.keyboard"
            fallback = "Keyboard"
        case .volume:
            key = "notch.hud.volume"
            fallback = "Volume"
        }
        if let locale = locale {
            return locale.dn(key, fallback: fallback)
        }
        return L10n.notch(key, fallback: fallback)
    }

    var title: String {
        title(locale: nil)
    }

    func symbolName(for level: Int) -> String {
        switch self {
        case .brightness:
            switch level {
            case ..<1:
                return "sun.min.fill"
            case ..<50:
                return "sun.min.fill"
            default:
                return "sun.max.fill"
            }

        case .keyboard:
            switch level {
            case ..<1:
                return "light.min"
            default:
                return "light.max"
            }

        case .volume:
            switch level {
            case ..<1:
                return "speaker.slash.fill"
            case ..<20:
                return "speaker.fill"
            case ..<50:
                return "speaker.wave.1.fill"
            case ..<70:
                return "speaker.wave.2.fill"
            default:
                return "speaker.wave.3.fill"
            }
        }
    }
}
