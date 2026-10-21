import SwiftUI

// Shared with Android's settings layout: 20 pt margins, 22 pt cards and 40 pt icon tiles.
struct SettingsPage<Content: View>: View {
    @ViewBuilder var content: () -> Content
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16, content: content)
                .frame(maxWidth: 640)
                .padding(20)
                .frame(maxWidth: .infinity)
        }
        .background(ClientTheme.background)
        .foregroundStyle(ClientTheme.text)
        .navigationBarTitleDisplayMode(.inline)
        .scrollDismissesKeyboard(.interactively)
    }
}

struct SettingsCard<Content: View>: View {
    @ViewBuilder var content: () -> Content
    var body: some View {
        VStack(alignment: .leading, spacing: 0, content: content)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(ClientTheme.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

struct SettingsSection<Content: View>: View {
    let title: String
    let icon: String
    @ViewBuilder var content: () -> Content
    var body: some View {
        SettingsCard {
            VStack(alignment: .leading, spacing: 18) {
                Label(title, systemImage: icon).font(.headline)
                content()
            }.padding(18)
        }
    }
}

struct SettingsSectionLabel: View {
    let title: String
    var body: some View {
        Text(title).font(.subheadline.weight(.medium)).foregroundStyle(ClientTheme.secondary)
            .padding(.leading, 8).padding(.top, 8)
    }
}

struct SettingsIcon: View {
    let name: String
    var body: some View {
        Image(systemName: name).font(.system(size: 20, weight: .regular))
            .frame(width: 40, height: 40)
            .background(ClientTheme.background, in: RoundedRectangle(cornerRadius: 12))
            .accessibilityHidden(true)
    }
}

struct SettingsRow: View {
    let title: String
    let icon: String
    var subtitle: String? = nil
    var body: some View {
        HStack(spacing: 14) {
            SettingsIcon(name: icon)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.body.weight(.medium))
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle).font(.caption).foregroundStyle(ClientTheme.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold))
                .foregroundStyle(ClientTheme.secondary).accessibilityHidden(true)
        }.padding(.horizontal, 16).padding(.vertical, 14)
            .foregroundStyle(ClientTheme.text).contentShape(Rectangle())
    }
}

struct SettingsDivider: View {
    var body: some View {
        Rectangle().fill(ClientTheme.text.opacity(0.08)).frame(height: 0.5)
            .padding(.leading, 70).padding(.trailing, 16)
    }
}

struct SettingsNote: View {
    let text: String
    var body: some View {
        Text(text).font(.footnote).foregroundStyle(ClientTheme.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

struct SettingsActionStyle: ButtonStyle {
    var prominent = true
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.body.weight(.semibold))
            .frame(maxWidth: .infinity).frame(minHeight: 48)
            .foregroundStyle(prominent ? ClientTheme.buttonText : ClientTheme.text)
            .background(prominent ? ClientTheme.accent : ClientTheme.surface,
                        in: RoundedRectangle(cornerRadius: 16))
            .opacity(enabled ? (configuration.isPressed ? 0.7 : 1) : 0.4)
    }
}

extension View {
    func settingsInput() -> some View {
        padding(14).frame(minHeight: 48)
            .background(ClientTheme.background, in: RoundedRectangle(cornerRadius: 12))
    }
}
