import SwiftUI

struct BeingIconButton: View {
    let title: LocalizedStringKey
    let systemImage: String
    let role: ButtonRole?
    let action: () -> Void

    init(_ title: LocalizedStringKey, systemImage: String, role: ButtonRole? = nil, action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.role = role
        self.action = action
    }

    var body: some View {
        Button(role: role, action: action) { Label(title, systemImage: systemImage) }
    }
}

struct BeingEmptyState<LabelContent: View, Description: View, Actions: View>: View {
    @ViewBuilder var label: () -> LabelContent
    @ViewBuilder var description: () -> Description
    @ViewBuilder var actions: () -> Actions

    var body: some View {
        if #available(iOS 17.0, *) {
            ContentUnavailableView(label: label, description: description, actions: actions)
        } else {
            VStack(spacing: 16) {
                label().labelStyle(EmptyStateLabelStyle())
                description().font(.subheadline).foregroundStyle(.secondary)
                actions()
            }
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(24)
        }
    }
}

extension BeingEmptyState where LabelContent == Label<Text, Image>, Description == Text?, Actions == EmptyView {
    init(_ title: LocalizedStringKey, systemImage: String, description: Text? = nil) {
        self.label = { Label(title, systemImage: systemImage) }
        self.description = { description }
        self.actions = { EmptyView() }
    }
}

private struct EmptyStateLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        VStack(spacing: 12) {
            configuration.icon.font(.system(size: 40)).foregroundStyle(.secondary)
            configuration.title.font(.headline)
        }
    }
}

extension View {
    @ViewBuilder func beingCircleButtonShape() -> some View {
        if #available(iOS 17.0, *) {
            buttonBorderShape(.circle)
        } else {
            clipShape(Circle())
        }
    }

    @ViewBuilder func beingPresentationBackground(_ color: Color) -> some View {
        if #available(iOS 16.4, *) {
            presentationBackground(color)
        } else {
            background(color.ignoresSafeArea())
        }
    }
}
