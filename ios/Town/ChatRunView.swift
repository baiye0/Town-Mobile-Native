import SwiftUI

/// The run exists before the first reply and keeps its place between the user
/// turn and its replies. Only progress supplied by the server is shown.
struct ChatRunView: View {
    let process: String
    let activity: String
    let isActive: Bool
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button { expanded.toggle() } label: {
                HStack(spacing: 8) {
                    if isActive { ProgressView().controlSize(.small) }
                    else { Image(systemName: "list.bullet.rectangle") }
                    Text(isActive ? (activity.isEmpty ? "思考中" : activity) : "思考与工具过程")
                    Spacer(minLength: 8)
                    if !process.isEmpty { Image(systemName: expanded ? "chevron.down" : "chevron.right") }
                }.contentShape(Rectangle())
            }.buttonStyle(.plain)
                .disabled(process.isEmpty)
                .accessibilityIdentifier(isActive ? "activeRunDetails" : "completedRunDetails")
                .accessibilityValue(expanded ? "已展开" : "已折叠")
            if expanded {
                Text(process).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("runProcessDetails")
            }
        }.font(.caption).foregroundStyle(ClientTheme.secondary)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .onChange(of: isActive) { if !$0 { expanded = false } }
    }
}
