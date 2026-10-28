//
//  BlipDropZoneContent.swift
//  DynamicNotch
//
//  Ablagefeld für Blip, im Stil des Tray-Felds.
//

import SwiftUI

struct BlipDropZoneContent: View {
    let isTargeted: Bool

    private var color: Color { DragAndDropTarget.blip.color }

    var body: some View {
        RoundedRectangle(cornerRadius: AirDropDropZoneMetrics.cornerRadius)
            .fill(isTargeted ? color.opacity(0.3) : color.opacity(0))
            .stroke(
                color.opacity(0.55),
                style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round, dash: [12, 6])
            )
            .overlay {
                VStack(spacing: 4) {
                    DragAndDropTarget.blip.icon()
                    DragAndDropTarget.blip.titleIcon()
                }
            }
    }
}
