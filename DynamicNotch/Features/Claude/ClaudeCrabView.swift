//
//  ClaudeCrabView.swift
//  DynamicNotch
//
//  Pixel-Krabbe ("Clawd") mit Kostümen, übertragen aus savvy-progress von
//  JohnnyVizz/claude-kit (MIT), das sie von DockCrab übernommen hat.
//  Raster 30 × 28. Beine treten abwechselnd, der Körper wippt; manche
//  Kostüme bewegen zusätzlich ihr Requisit.
//

import SwiftUI

enum CrabCostume: String, CaseIterable, Sendable {
    case plain, astronaut, detective, engineer, chef, racer, pirate

    /// Kostüm passend zur Art des Subagenten
    static func forSubagent(type: String, index: Int) -> CrabCostume {
        switch type.lowercased() {
        case "explore": return .pirate
        case "plan": return .detective
        case "general-purpose": return .engineer
        case "claude-code-guide": return .astronaut
        default:
            let rotation: [CrabCostume] = [.chef, .racer, .astronaut, .detective, .engineer]
            return rotation[index % rotation.count]
        }
    }

    /// Farbe des Kostüms (bei savvy-progress die Farbe der Modellstufe)
    var accent: Color {
        switch self {
        case .plain: ClaudeStyle.accent
        case .astronaut: Color(red: 0.55, green: 0.48, blue: 0.95)
        case .detective: Color(red: 0.30, green: 0.55, blue: 0.85)
        case .engineer: Color(red: 0.25, green: 0.65, blue: 0.55)
        case .chef: Color(red: 0.85, green: 0.47, blue: 0.34)
        case .racer: Color(red: 0.85, green: 0.30, blue: 0.30)
        case .pirate: Color(red: 0.95, green: 0.77, blue: 0.26)
        }
    }
}

struct ClaudeCrabView: View {
    var costume: CrabCostume = .plain
    var isWalking: Bool
    var height: CGFloat = 20
    var dimmed = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.125)) { context in
            let tick = Int(context.date.timeIntervalSinceReferenceDate / 0.125)
            Canvas { graphics, size in
                draw(in: &graphics, size: size, tick: isWalking ? tick : 0)
            }
        }
        .frame(width: height * 30 / 28, height: height)
        .opacity(dimmed ? 0.45 : 1)
    }

    private func draw(in graphics: inout GraphicsContext, size: CGSize, tick: Int) {
        let unit = size.width / 30
        // Ein Schritt dauert 0,5 s (4 Ticks); Rennfahrer laufen doppelt so schnell
        let stepTicks = costume == .racer ? 1 : 2
        let step = (tick / stepTicks) % 2
        let bob: CGFloat = isWalking && ((tick + 1) / stepTicks) % 2 == 0 ? 1 : 0
        let float: CGFloat = costume == .astronaut && isWalking ? (tick % 8 < 4 ? -1 : 0) : 0

        var pixels = CrabPixels()
        CrabPixels.body(&pixels, armFront: costume.raisesArm ? -4 : 0)
        costume.dressUp(&pixels, tick: isWalking ? tick : 0)

        for pixel in pixels.items {
            var dy: CGFloat = 0
            switch pixel.group {
            case .legA where costume != .astronaut: dy = step == 0 ? -1 : 0
            case .legB where costume != .astronaut: dy = step == 1 ? -1 : 0
            case .legA, .legB: dy = float
            case .body, .prop: dy = (costume == .astronaut ? float : bob) + pixel.extraY
            }
            let rect = CGRect(
                x: (pixel.x + pixel.extraX) * unit,
                y: (pixel.y + dy) * unit,
                width: pixel.w * unit,
                height: pixel.h * unit
            )
            graphics.fill(Path(rect), with: .color(pixel.color.opacity(pixel.opacity)))
        }
    }
}

// MARK: - Pixel

struct CrabPixels {
    enum Group { case body, legA, legB, prop }

    struct Pixel {
        let x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat
        let color: Color
        let group: Group
        var extraX: CGFloat = 0
        var extraY: CGFloat = 0
        var opacity: Double = 1
    }

    static let clay = Color(red: 0xD9 / 255, green: 0x77 / 255, blue: 0x57 / 255)
    static let ink = Color(red: 0x1F / 255, green: 0x1E / 255, blue: 0x1D / 255)

    var items: [Pixel] = []

    mutating func fill(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ color: Color,
                       _ group: Group = .body, dx: CGFloat = 0, dy: CGFloat = 0, opacity: Double = 1) {
        items.append(Pixel(x: x, y: y, w: w, h: h, color: color, group: group, extraX: dx, extraY: dy, opacity: opacity))
    }

    /// Zeichnet Zeilen wie ["..bb..", ".bbbb."]; jedes Zeichen ist ein Pixel aus `colors`
    mutating func stamp(_ x: CGFloat, _ y: CGFloat, _ rows: [String], _ colors: [Character: Color],
                        _ group: Group = .body, dx: CGFloat = 0, dy: CGFloat = 0, opacity: Double = 1) {
        for (row, line) in rows.enumerated() {
            for (column, character) in line.enumerated() {
                if let color = colors[character] {
                    fill(x + CGFloat(column), y + CGFloat(row), 1, 1, color, group, dx: dx, dy: dy, opacity: opacity)
                }
            }
        }
    }

    static func body(_ p: inout CrabPixels, armFront: CGFloat) {
        p.fill(7, 10, 16, 12, clay)
        p.fill(3, 14, 4, 4, clay)
        p.fill(23, 14 + armFront, 4, 4, clay)
        p.fill(9, 12, 2, 2, ink)
        p.fill(19, 12, 2, 2, ink)
        p.fill(7, 22, 2, 4, clay, .legA)
        p.fill(17, 22, 2, 4, clay, .legA)
        p.fill(11, 22, 2, 4, clay, .legB)
        p.fill(21, 22, 2, 4, clay, .legB)
    }
}

private extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: alpha
        )
    }
}

private extension CrabCostume {
    var raisesArm: Bool {
        switch self {
        case .detective, .chef, .racer: true
        default: false
        }
    }

    func dressUp(_ p: inout CrabPixels, tick: Int) {
        let t = accent
        let half = tick % 4 < 2          // halber Takt (0,25 s)
        let beat = tick % 8 < 4          // ganzer Takt (0,5 s)

        switch self {
        case .plain:
            break

        case .astronaut:
            // Glaskuppel; Antenne und Stern blinken
            p.fill(6, 7, 18, 1, Color(hex: 0xE6E8EE)); p.fill(5, 8, 1, 14, Color(hex: 0xE6E8EE))
            p.fill(24, 8, 1, 14, Color(hex: 0xE6E8EE)); p.fill(6, 22, 18, 1, Color(hex: 0xC9CCD2))
            p.fill(6, 8, 18, 14, Color(red: 169 / 255, green: 214 / 255, blue: 245 / 255, opacity: 0.32))
            p.fill(8, 9, 2, 1, .white); p.fill(8, 10, 1, 2, .white)
            p.fill(14, 4, 2, 3, Color(hex: 0xC9CCD2)); p.fill(14, 2, 2, 2, t, .prop, opacity: beat ? 1 : 0.15)
            p.fill(13, 18, 4, 2, t)
            p.fill(27, 3, 1, 3, Color(hex: 0xF5C542), .prop, opacity: half ? 1 : 0.15)
            p.fill(26, 4, 3, 1, Color(hex: 0xF5C542), .prop, opacity: half ? 1 : 0.15)

        case .detective:
            // Deerstalker-Mütze; die Lupe kreist
            p.stamp(6, 3, ["......bbbbbb......", "....bbcbbcbbbb....", "...bbbbbbbbbbbb...",
                           "..bcbbcbbcbbcbbb..", ".bbbbbbbbbbbbbbbb.", "dddddddddddddddddd"],
                    ["b": Color(hex: 0x7A4A26), "c": Color(hex: 0xA0703F), "d": Color(hex: 0x5A3519)])
            p.fill(6, 9, 18, 1, t)
            let sweep: CGFloat = [0, -1, -2, -1][(tick / 2) % 4]
            p.stamp(23, 1, [".kkk.", "k...k", "k...k", "k...k", ".kkk."], ["k": Color(hex: 0x3A3A3C)], .prop, dx: sweep, dy: -sweep)
            p.fill(24, 2, 3, 3, Color(red: 169 / 255, green: 214 / 255, blue: 245 / 255, opacity: 0.7), .prop, dx: sweep, dy: -sweep)
            p.fill(25, 6, 1, 4, Color(hex: 0x7A4A26), .prop, dx: sweep, dy: -sweep)
            p.fill(24, 2, 1, 1, .white, .prop, dx: sweep, dy: -sweep, opacity: beat ? 1 : 0.15)

        case .engineer:
            // Bauhelm; der Schraubenschlüssel dreht
            p.stamp(6, 4, [".....yyyyyyyy.....", "...yyyyyhhyyyyy...", "..yyyyyyhhyyyyyy..",
                           "..yyyyyyhhyyyyyy..", ".yyyyyyyhhyyyyyyy.", "dddddddddddddddddd"],
                    ["y": Color(hex: 0xF5C542), "h": Color(hex: 0xFBE08A), "d": Color(hex: 0xC99A1E)])
            p.fill(13, 5, 4, 2, t)
            p.stamp(0, 10, [".s.s", "sss.", ".s..", ".s.."], ["s": Color(hex: 0x8E929A)], .prop, dy: half ? -1 : 0)

        case .chef:
            // Kochmütze; das Omelett fliegt aus der Pfanne
            p.stamp(6, 0, ["........lll.......", ".......lllll......", ".wwwwgwwwwwwgwwwww", "wwwwwwwwwwwwwwwwww",
                           "wwwwwwwwwwwwwwwwww", "wwwwwgwwwwwggwwwww", ".wwwwgwwwwwggwwwww", ".dddbbbbbbbbbbbbb.",
                           ".dddbbbbbbbbbbbbb.", ".dddbbbbbbbbbbbbb."],
                    ["w": Color(hex: 0xF4F3EE), "l": Color(hex: 0xF7F6F2), "g": Color(hex: 0xD2D1C8), "b": t, "d": Color(hex: 0xB45F43)])
            p.fill(22, 8, 7, 2, Color(hex: 0x4A4A48), .prop); p.fill(26, 10, 1, 1, Color(hex: 0x4A4A48), .prop)
            p.fill(24, 7, 3, 1, Color(hex: 0xF5B731), .prop, dy: tick % 8 < 3 ? -4 : 0)

        case .racer:
            // Helm; die Zielflagge flattert
            p.stamp(6, 5, ["....rrrrrrrrrr....", "..rrrrrrwwrrrrrr..", ".rrrrrrrwwrrrrrrr.",
                           ".rrrrrrrwwrrrrrrr.", ".rrrrrrrwwrrrrrrr.", ".kkkkkkkkkkkkkkkkr"],
                    ["r": t, "w": Color(hex: 0xF8F6F1), "k": CrabPixels.ink])
            p.fill(25, 1, 1, 9, Color(hex: 0x8E929A))
            p.stamp(26, 1, half ? ["wkwk", "kwkw", "wkwk"] : ["kwkw", "wkwk", "kwkw"],
                    ["w": Color(hex: 0xF8F6F1), "k": CrabPixels.ink], .prop)

        case .pirate:
            // Dreispitz und Augenklappe; der Säbel ficht
            p.stamp(5, 3, [".kk..............kk.", ".kkk....kkkk....kkk.", "..kkkkkkkwwkkkkkkk..",
                           "..kkkkkkkkkkkkkkkk..", ".gggggggggggggggggg."],
                    ["k": Color(hex: 0x55514C), "w": Color(hex: 0xF8F6F1), "g": Color(hex: 0xF5C542)])
            p.fill(7, 11, 11, 1, CrabPixels.ink); p.fill(18, 11, 4, 3, CrabPixels.ink)
            let lunge: CGFloat = beat ? 0 : 1
            p.fill(27, 6, 1, 9, Color(hex: 0xC9CCD2), .prop, dx: lunge, dy: -lunge)
            p.fill(26, 15, 3, 1, Color(hex: 0x7A4A26), .prop, dx: lunge, dy: -lunge)
        }
    }
}
