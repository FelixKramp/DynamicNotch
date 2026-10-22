//
//  TimerCountdownText.swift
//  DynamicNotch
//
//  Created by Евгений Петрукович on 4/17/26.
//

import SwiftUI

struct TimerCountdownText: View {
    let source: TimerSource
    
    @Environment(\.isNotchlessScreen) private var isNotchlessScreen

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.25, paused: source.isPaused)) { context in
            let formatted = source.formattedTime(at: context.date)
            Text(formatted)
                .font(.system(size: 14, design: .rounded))
                .foregroundStyle(.orange.gradient)
                .monospacedDigit()
        }
    }
}
