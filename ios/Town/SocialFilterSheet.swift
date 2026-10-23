import SwiftUI

struct SocialAction: View {
    let title: String
    let icon: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: 20)).frame(width: 44, height: 44).contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityLabel(title)
    }
}

struct SocialChoiceChips<Value: Hashable>: View {
    let options: [(Value, String)]
    @Binding var selection: Value
    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) { choices }.fixedSize(horizontal: true, vertical: false)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 8)], alignment: .leading, spacing: 8) { choices }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private var choices: some View {
        ForEach(options, id: \.0) { value, title in
            Button { selection = value } label: {
                Text(title).font(.subheadline.weight(selection == value ? .semibold : .regular))
                    .padding(.horizontal, 16).padding(.vertical, 10).frame(minHeight: 44)
                    .foregroundStyle(selection == value ? ClientTheme.buttonText : ClientTheme.text)
                    .background(selection == value ? ClientTheme.accent : ClientTheme.surface, in: Capsule())
                    .fixedSize(horizontal: false, vertical: true).multilineTextAlignment(.center)
            }.buttonStyle(.plain).accessibilityAddTraits(selection == value ? .isSelected : [])
        }
    }
}

struct SocialFilterSheet: View {
    let roomList: Bool
    let kind: Destination
    @Binding var search: String
    @Binding var filters: FeedFilter
    @Binding var limit: Int
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    HStack(spacing: 10) {
                        Image(systemName: "magnifyingglass").foregroundStyle(ClientTheme.secondary)
                        TextField(roomList ? "围炉名称" : "消息或 Being", text: $search).autocorrectionDisabled()
                        if !search.isEmpty { Button { search = "" } label: { Image(systemName: "xmark.circle.fill") }.accessibilityLabel("清除搜索") }
                    }.padding(14).background(ClientTheme.surface, in: RoundedRectangle(cornerRadius: 14))
                    if !roomList {
                        SettingsNote(text: "搜索和筛选作用于当前已加载消息。")
                        TextField("作者名称或 ID", text: $filters.author).autocorrectionDisabled()
                            .padding(14).background(ClientTheme.surface, in: RoundedRectangle(cornerRadius: 14))
                        filterGroup("与我的关系") {
                            SocialChoiceChips(options: [("all", "全部"), ("about", "与我有关"), ("mentions", "提到我"), ("mine", "我发送的")], selection: $filters.relation)
                        }
                        filterGroup("时间范围") {
                            SocialChoiceChips(options: [(0, "不限"), (1, "一天"), (7, "七天"), (30, "三十天")], selection: $filters.days)
                        }
                        filterGroup("消息顺序") {
                            SocialChoiceChips(options: [(false, "最新优先"), (true, "最早优先")], selection: $filters.oldestFirst)
                        }
                        if kind == .bonfire {
                            filterGroup("加载条数") {
                                SocialChoiceChips(options: [(50, "50 条"), (100, "100 条"), (200, "200 条")], selection: $limit)
                            }
                        }
                    }
                    Button("查看结果") { dismiss() }.buttonStyle(SettingsActionStyle())
                }.padding(24).frame(maxWidth: 680).frame(maxWidth: .infinity)
            }.scrollDismissesKeyboard(.interactively).background(ClientTheme.background)
                .foregroundStyle(ClientTheme.text)
                .navigationTitle(roomList ? "搜索围炉" : "搜索与筛选").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("重置") { search = ""; filters = FeedFilter() } }
                    ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } }
                }
        }.presentationDetents([.large]).presentationDragIndicator(.visible)
    }
    private func filterGroup<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.subheadline.weight(.semibold))
            content()
        }
    }
}
