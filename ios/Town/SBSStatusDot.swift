import SwiftUI

struct SBSStatusDot: View {
    let enabled: Bool
    let active: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 20, paused: !active || reduceMotion)) { context in
            let pulse = active && !reduceMotion ? (sin(context.date.timeIntervalSinceReferenceDate * .pi * 2 / 1.6) + 1) / 2 : 1
            Circle()
                .fill(enabled || active ? ClientTheme.color(0x36935c, 0x7fc797) : .clear)
                .overlay { Circle().strokeBorder(enabled || active ? ClientTheme.color(0x36935c, 0x7fc797) : ClientTheme.secondary, lineWidth: 2) }
                .frame(width: 10, height: 10)
                .opacity(0.45 + 0.55 * pulse)
                .scaleEffect(0.9 + 0.1 * pulse)
        }.frame(width: 14, height: 14).accessibilityHidden(true)
    }
}
