import SwiftUI

// Keep iOS 18's scroll phase handling, with geometry/drag tracking for iOS 16–17.
struct ChatScrollBehavior: ViewModifier {
    @Binding var nearBottom: Bool
    @Binding var followLatest: Bool
    @Binding var userScrolling: Bool
    @Binding var bottomRequest: Int
    let legacyMetrics: LegacyChatScrollMetrics
    @Binding var viewportHeight: CGFloat
    @State private var scrollingTowardBottom = false
    @State private var previousContentHeight: CGFloat = 0
    @State private var lastDragTranslation: CGFloat = 0
    @GestureState private var legacyDragging = false

    @ViewBuilder func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content
                .defaultScrollAnchor(.bottom, for: .initialOffset)
                .defaultScrollAnchor(followLatest ? .bottom : nil, for: .sizeChanges)
                .onScrollPhaseChange { _, phase in
                    let wasUserScrolling = userScrolling
                    userScrolling = phase == .tracking || phase == .interacting || phase == .decelerating
                    if phase == .tracking { scrollingTowardBottom = false }
                    if userScrolling { followLatest = false }
                    if phase == .idle && wasUserScrolling && nearBottom && scrollingTowardBottom { followLatest = true }
                }
                .onScrollGeometryChange(for: ChatScrollMetrics.self) { geometry in
                    ChatScrollMetrics(bottom: geometry.contentSize.height - geometry.visibleRect.maxY < 80,
                                      offset: geometry.contentOffset.y, height: geometry.contentSize.height)
                } action: { old, metrics in
                    // Geometry observes position only. Issuing scroll commands
                    // here creates a feedback loop as LazyVStack estimates heights.
                    nearBottom = metrics.bottom
                    if userScrolling && old.height == metrics.height && old.offset != metrics.offset {
                        scrollingTowardBottom = metrics.offset > old.offset
                        if !scrollingTowardBottom { followLatest = false }
                    }
                }
        } else {
            content
                .onAppear { if followLatest { bottomRequest += 1 } }
                .coordinateSpace(name: "chatScroll")
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                    viewportHeight = height
                    updateLegacyPosition(legacyMetrics)
                }
                .onChange(of: legacyMetrics) { metrics in
                    let oldHeight = previousContentHeight
                    previousContentHeight = metrics.height
                    updateLegacyPosition(metrics)
                    if oldHeight != metrics.height, followLatest, !userScrolling { bottomRequest += 1 }
                }
                .onChange(of: followLatest) { following in
                    if !following && !userScrolling { scrollingTowardBottom = false }
                }
                .onChange(of: legacyDragging) { dragging in
                    userScrolling = dragging
                    if !dragging {
                        lastDragTranslation = 0
                        if nearBottom && scrollingTowardBottom { followLatest = true }
                    }
                }
                .onDisappear { userScrolling = false }
                .simultaneousGesture(DragGesture(minimumDistance: 1)
                    .updating($legacyDragging) { _, dragging, _ in dragging = true }
                    .onChanged { value in
                        followLatest = false
                        scrollingTowardBottom = value.translation.height < lastDragTranslation
                        lastDragTranslation = value.translation.height
                    })
        }
    }

    private func updateLegacyPosition(_ metrics: LegacyChatScrollMetrics) {
        guard viewportHeight > 0, metrics.height > 0 else { return }
        nearBottom = metrics.bottom
        // A drag can coast to the bottom after the finger is lifted.
        if nearBottom && scrollingTowardBottom && !userScrolling { followLatest = true }
    }
}

struct LegacyChatContentGeometry: ViewModifier {
    let viewportHeight: CGFloat
    @Binding var metrics: LegacyChatScrollMetrics
    @ViewBuilder func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content
        } else {
            // Direct observation also updates when LazyVStack's preferences
            // aren't propagated through ScrollView on iOS 16.
            // Publish only bottom proximity and content height, so scrolling
            // doesn't rebuild the entire message list for every pixel.
            content.onGeometryChange(for: LegacyChatScrollMetrics.self) { geometry in
                let frame = geometry.frame(in: .named("chatScroll"))
                return LegacyChatScrollMetrics(bottom: frame.maxY - viewportHeight < 80, height: frame.height)
            } action: { metrics = $0 }
        }
    }
}

struct LegacyChatScrollMetrics: Equatable {
    var bottom = true
    var height: CGFloat = 0
}
private struct ChatScrollMetrics: Equatable { var bottom: Bool; var offset: CGFloat; var height: CGFloat }

struct StreamReplyGeometry: ViewModifier {
    let tracked: Bool
    let viewportHeight: CGFloat
    @Binding var fillsViewport: Bool
    @ViewBuilder func body(content: Content) -> some View {
        if tracked {
            content.onGeometryChange(for: Bool.self) { geometry in
                viewportHeight > 0 && geometry.size.height >= viewportHeight - 20
            } action: { fillsViewport = $0 }
        } else { content }
    }
}
