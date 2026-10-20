import SwiftUI

@MainActor final class PageHistory: ObservableObject {
    @Published var path: [UUID] = []
    @Published var forward: [UUID] = []
    @Published var pages: [UUID: AnyView] = [:]
    func navigate(_ next: [UUID]) {
        if next.count < path.count && Array(path.prefix(next.count)) == next {
            forward.insert(contentsOf: path.dropFirst(next.count), at: 0)
        } else if next != path { forward.removeAll() }
        path = next
    }
    func back() { guard !path.isEmpty else { return }; navigate(Array(path.dropLast())) }
    func advance() {
        guard let id = forward.first else { return }
        forward.removeFirst(); path.append(id)
    }
}
private struct PageHistoryKey: EnvironmentKey { static let defaultValue: PageHistory? = nil }
extension EnvironmentValues {
    var pageHistory: PageHistory? {
        get { self[PageHistoryKey.self] }
        set { self[PageHistoryKey.self] = newValue }
    }
}
struct HistoryStack<Content: View>: View {
    @Environment(\.pageHistory) private var inherited
    @StateObject private var history = PageHistory()
    @AppStorage("glassEffects") private var glass = true
    @ViewBuilder var content: () -> Content
    var body: some View {
        if inherited != nil { content() }
        else {
            NavigationStack(path: Binding(get: { history.path }, set: { history.navigate($0) })) {
                content().navigationDestination(for: UUID.self) { id in
                    history.pages[id]
                        .navigationBarBackButtonHidden(!glass)
                        .toolbar {
                            if !glass {
                                AdaptiveToolbar {
                                    ToolbarItem(placement: .navigationBarLeading) {
                                        Button { history.back() } label: { Image(systemName: "chevron.left") }.accessibilityLabel("返回")
                                    }
                                }
                            }
                        }
                }
            }
            .environment(\.pageHistory, history)
            .overlay(alignment: .leading) {
                if !history.path.isEmpty {
                    Color.clear.frame(width: 20).contentShape(Rectangle())
                        .gesture(DragGesture(minimumDistance: 20).onEnded { value in
                            if value.translation.width > 60 && abs(value.translation.width) > abs(value.translation.height) * 1.5 {
                                withAnimation { history.back() }
                            }
                        }).accessibilityHidden(true)
                }
            }
            .overlay(alignment: .trailing) {
                if !history.forward.isEmpty {
                    Color.clear.frame(width: 20).contentShape(Rectangle())
                        .gesture(DragGesture(minimumDistance: 20).onEnded { value in
                            if value.translation.width < -60 && abs(value.translation.width) > abs(value.translation.height) * 1.5 {
                                withAnimation { history.advance() }
                            }
                        }).accessibilityHidden(true)
                }
            }
            .accessibilityAction(named: Text("前进")) { withAnimation { history.advance() } }
        }
    }
}
struct HistoryLink<Content: View, LabelView: View>: View {
    @Environment(\.pageHistory) private var history
    @State private var id = UUID()
    var destination: () -> Content
    var label: () -> LabelView
    init(@ViewBuilder destination: @escaping () -> Content, @ViewBuilder label: @escaping () -> LabelView) {
        self.destination = destination; self.label = label
    }
    init(_ title: String, @ViewBuilder destination: @escaping () -> Content) where LabelView == Text {
        self.destination = destination; self.label = { Text(title) }
    }
    var body: some View {
        if let history {
            NavigationLink(value: id, label: label)
                .onAppear { history.pages[id] = AnyView(destination()) }
        } else { NavigationLink(destination: destination, label: label) }
    }
}
