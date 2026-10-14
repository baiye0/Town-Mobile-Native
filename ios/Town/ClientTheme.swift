import SwiftUI
// desktop/renderer/app/styles.css, light and dark tokens.
enum ClientTheme {
    static func color(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(uiColor: UIColor { traits in
            let value = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: CGFloat((value >> 16) & 255) / 255, green: CGFloat((value >> 8) & 255) / 255, blue: CGFloat(value & 255) / 255, alpha: 1)
        })
    }
    static let background = color(0xffffff,0x212121)
    static let surface = color(0xf7f7f6,0x292929)
    static let text = color(0x242424,0xececec)
    static let secondary = color(0x686868,0xadadad)
    static let accent = color(0x292929,0xececec)
    // Muse screenshot: blue sent bubble and neutral received bubble.
    static let chatSent = color(0x007aff,0x007aff)
    static let chatReply = color(0xebebed,0x383838)
    static let buttonText = color(0xffffff,0x242424)
    // Desktop Town feed tokens (styles.css:840–845).
    static let feedAction = color(0x1767c4,0x8abbff)
    static let feedTint = color(0xeaf3ff,0x273b54)
    static let fireInk = color(0x9b562b,0xedba85)
    static let fireTint = color(0xf7ecdf,0x41352b)
    static func socialCard(_ kind: Destination) -> Color {
        switch kind {
        case .mail: color(0xf0f6ff,0x25303e)
        case .bonfire: color(0xfbf1e5,0x352d26)
        default: color(0xf7f3ee,0x302b27)
        }
    }
}

struct AdaptiveToolbar<Content: ToolbarContent>: ToolbarContent {
    @AppStorage("glassEffects") private var glass = true
    @ToolbarContentBuilder var content: () -> Content
    var body: some ToolbarContent { content().sharedBackgroundVisibility(glass ? .automatic : .hidden) }
}
private struct AdaptiveSurface: ViewModifier {
    @AppStorage("glassEffects") private var glass = true
    let radius: CGFloat
    @ViewBuilder func body(content: Content) -> some View {
        if glass { content.glassEffect(.regular, in: RoundedRectangle(cornerRadius: radius)) }
        else { content.background(ClientTheme.surface, in: RoundedRectangle(cornerRadius: radius)) }
    }
}
private struct AdaptiveButton: ViewModifier {
    @AppStorage("glassEffects") private var glass = true
    let prominent: Bool
    @ViewBuilder func body(content: Content) -> some View {
        if glass {
            if prominent { content.buttonStyle(.glassProminent) } else { content.buttonStyle(.glass) }
        } else {
            content.buttonStyle(SolidActionButtonStyle(prominent: prominent))
        }
    }
}
extension View {
    func beingSurface(radius: CGFloat) -> some View { modifier(AdaptiveSurface(radius: radius)) }
    func beingButton(prominent: Bool = false) -> some View { modifier(AdaptiveButton(prominent: prominent)) }
}

struct BeingDefaultButtonStyle: PrimitiveButtonStyle {
    @AppStorage("glassEffects") private var glass = true
    @ViewBuilder func makeBody(configuration: Configuration) -> some View {
        if glass { Button(action: configuration.trigger) { configuration.label }.buttonStyle(.automatic) }
        else { Button(action: configuration.trigger) { configuration.label }.buttonStyle(.plain) }
    }
}
struct BeingToggleStyle: ToggleStyle {
    @AppStorage("glassEffects") private var glass = true
    @Environment(\.isEnabled) private var enabled
    @ViewBuilder func makeBody(configuration: Configuration) -> some View {
        if glass { Toggle(isOn: configuration.$isOn) { configuration.label }.toggleStyle(.switch) }
        else {
            HStack {
                configuration.label
                Spacer(minLength: 12)
                Button { withAnimation(.easeOut(duration: 0.15)) { configuration.isOn.toggle() } } label: {
                    Capsule().fill(configuration.isOn ? ClientTheme.accent : ClientTheme.secondary.opacity(0.3))
                        .frame(width: 51, height: 31)
                        .overlay(alignment: configuration.isOn ? .trailing : .leading) {
                            Circle().fill(configuration.isOn ? ClientTheme.buttonText : ClientTheme.text).frame(width: 25, height: 25).padding(3)
                        }.frame(width: 51, height: 44)
                }.buttonStyle(.plain)
                    .accessibilityLabel(Text(configuration.isOn ? "开启" : "关闭"))
            }.opacity(enabled ? 1 : 0.45)
                .accessibilityElement(children: .ignore)
                .accessibilityRepresentation { Toggle(isOn: configuration.$isOn) { configuration.label }.toggleStyle(.switch) }
        }
    }
}

private struct SolidActionButtonStyle: ButtonStyle {
    let prominent: Bool
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, prominent ? 16 : 0).padding(.vertical, prominent ? 10 : 0)
            .foregroundStyle(prominent ? ClientTheme.buttonText : ClientTheme.accent)
            .background(prominent ? ClientTheme.accent : ClientTheme.surface, in: RoundedRectangle(cornerRadius: 12))
            .opacity(enabled ? (configuration.isPressed ? 0.7 : 1) : 0.4)
    }
}
