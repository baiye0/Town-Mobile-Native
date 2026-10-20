import SwiftUI
struct AnnouncementStrip: View {
    @EnvironmentObject private var social: SocialStore
    @State private var entries: [CatalogRecord] = []
    @State private var index = 0
    private var regular: [CatalogRecord] { entries.filter { $0.data["pinned"] as? Bool != true } }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(entries.filter { $0.data["pinned"] as? Bool == true }.prefix(3))) { entry in
                HistoryLink { CatalogDetail(category: "announcements", record: entry) } label: { Label("置顶 · " + field(entry.data,"title"), systemImage: "pin.fill").lineLimit(2) }
            }
            if !regular.isEmpty { let entry = regular[index % regular.count]; HistoryLink { CatalogDetail(category: "announcements", record: entry) } label: { Label(field(entry.data,"title"), systemImage: "megaphone").lineLimit(2) } }
        }.font(.subheadline).task(id: social.revision) {
            if let data = try? await social.request("/api/announcements?limit=50&include_expired=false", privateRoute: false) { entries = (data["items"] as? [[String: Any]] ?? []).compactMap { value in let id = field(value,"id"); return id.isEmpty ? nil : CatalogRecord(id:id,data:value) } }
        }.task { while !Task.isCancelled { do { try await Task.sleep(for: .seconds(8)); index = (index + 1) % max(1, regular.count) } catch { return } } }
    }
}
