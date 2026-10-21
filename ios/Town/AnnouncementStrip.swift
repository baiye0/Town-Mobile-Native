import SwiftUI

struct AnnouncementStrip: View {
    @EnvironmentObject private var social: SocialStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var entries: [CatalogRecord] = []
    @State private var index = 0
    private var ordered: [CatalogRecord] {
        entries.filter { $0.data["pinned"] as? Bool == true } + entries.filter { $0.data["pinned"] as? Bool != true }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !ordered.isEmpty {
                let entry = ordered[index % ordered.count]
                HistoryLink { CatalogDetail(category: "announcements", record: entry) } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "megaphone").font(.system(size: 17)).accessibilityHidden(true)
                        Text((entry.data["pinned"] as? Bool == true ? "置顶 · " : "") + field(entry.data, "title"))
                            .font(.subheadline).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                        if ordered.count > 1 {
                            Text("\(index % ordered.count + 1)/\(ordered.count)").font(.caption).monospacedDigit().foregroundStyle(ClientTheme.secondary)
                        }
                    }.padding(.horizontal, 14).frame(minHeight: 48)
                        .background(ClientTheme.surface, in: RoundedRectangle(cornerRadius: 14)).contentShape(Rectangle())
                }.buttonStyle(.plain).foregroundStyle(ClientTheme.text).id(entry.id)
                    .accessibilityIdentifier("announcementStrip")
            }
        }.task(id: social.revision) {
            if let data = try? await social.request("/api/announcements?limit=50&include_expired=false", privateRoute: false) {
                entries = (data["items"] as? [[String: Any]] ?? []).compactMap { value in
                    let id = field(value, "id"); return id.isEmpty ? nil : CatalogRecord(id: id, data: value)
                }
            }
        }.task(id: reduceMotion) {
            guard !reduceMotion else { return }
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(8)); index = (index + 1) % max(1, ordered.count) }
                catch { return }
            }
        }
    }
}
