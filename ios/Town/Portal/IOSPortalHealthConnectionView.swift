import SwiftUI

struct IOSPortalHealthConnectionView: View {
    @ObservedObject var portal: IOSPortalStore
    @Environment(\.dismiss) private var dismiss
    @State private var completed = false
    var body: some View {
        ScrollView {
            VStack(spacing: 26) {
                VStack(spacing: 14) {
                    Image(systemName: "heart.fill")
                        .font(.system(size: 38))
                        .foregroundStyle(LinearGradient(colors: [.pink, .red], startPoint: .top, endPoint: .bottom))
                        .frame(width: 78, height: 78)
                        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20))
                    Text("健康").font(.title2.bold())
                    Text("让 \(portal.connection?.being ?? "当前 Being") 了解你的健康与活动")
                        .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }.padding(.top, 20)
                if completed {
                    VStack(alignment: .leading, spacing: 24) {
                        detail("link", "关联请求已完成", "当前 Being 已连接 Apple 健康数据来源，实际可读取的内容取决于你的系统共享设置。这不表示所有健康数据都已获准读取。")
                        detail("slider.horizontal.3", "没有出现系统选择页？", "iOS 可能沿用你之前的选择，不再重复弹窗。要开启或调整共享，请打开健康 App → 个人头像 → App（或 App 与服务）→ Being。")
                    }.accessibilityIdentifier("portalHealthResult")
                } else {
                    VStack(alignment: .leading, spacing: 24) {
                        detail("chart.bar.xaxis", "连接你的健康数据", "共享你选择的活动、睡眠、锻炼、心肺和身体指标，包括营养、步态、跑步指标、正念、生理周期、血氧、血压和体脂等 \(IOSPortalHealth.categories.count) 类数据。")
                        detail("slider.horizontal.3", "由你选择共享范围", "点击继续后向系统发起关联。首次请求会显示健康共享选择页；已选择过的项目可能不再弹窗。Being 只能读取系统允许的内容，不会修改健康记录。")
                        detail("link", "随时断开关联", "你可以在 Portal 中断开，停止后续查询。关联只对当前 Being 生效，查询需要应用在前台且 Portal 已启动。")
                    }
                }
                Divider()
                Text("共享的数据会发送给当前 Being；断开不会删除它已收到的数据。iOS 不向 App 透露每类数据是否允许读取，关联状态不代表全部数据可用。")
                    .font(.footnote).foregroundStyle(.secondary)
                if let notice = portal.notice { Text(notice).font(.footnote).foregroundStyle(.red) }
                VStack(spacing: 12) {
                    if completed {
                        Button("完成") { dismiss() }
                            .font(.headline).frame(maxWidth: .infinity).frame(minHeight: 52)
                            .buttonStyle(.borderedProminent)
                            .accessibilityIdentifier("portalHealthDone")
                    } else {
                        Button {
                            Task {
                                completed = await portal.connectHealth()
                            }
                        } label: {
                            HStack {
                                if portal.healthRequesting { ProgressView().tint(.white) }
                                Text(portal.healthRequesting ? "正在关联…" : "继续").font(.headline)
                            }.frame(maxWidth: .infinity).frame(minHeight: 52)
                        }.buttonStyle(.plain).foregroundStyle(.white)
                            .background(LinearGradient(colors: [.blue, .indigo], startPoint: .leading, endPoint: .trailing), in: Capsule())
                            .disabled(portal.healthRequesting || !portal.health.available)
                            .accessibilityIdentifier("portalHealthContinue")
                        Button("取消") { dismiss() }.font(.headline).frame(minHeight: 44)
                            .disabled(portal.healthRequesting).accessibilityIdentifier("portalHealthCancel")
                    }
                }
            }.padding(24)
        }.background(Color(uiColor: .systemBackground))
    }
    private func detail(_ icon: String, _ title: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon).font(.title3).frame(width: 26).padding(.top, 2)
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.headline)
                Text(text).font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
