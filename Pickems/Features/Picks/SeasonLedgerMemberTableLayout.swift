import SwiftUI

/// Split table: pinned leading column + member columns with optional shared horizontal scroll.
enum SeasonLedgerMemberTableLayout {
    /// Members beyond this count share a single horizontal `ScrollView` for every row band.
    static let sharedScrollMemberThreshold = 4

    static func usesSharedHorizontalScroll(memberCount: Int) -> Bool {
        memberCount > sharedScrollMemberThreshold
    }

    static var sharedMemberScrollAccessibilityId: String { "seasonLedger.sharedMemberScroll" }

    /// Width of one member column when the roster fits without horizontal scroll.
    static func flexibleMemberColumnWidth(memberCount: Int, availableMemberBandWidth: CGFloat) -> CGFloat {
        guard memberCount > 0, availableMemberBandWidth > 0 else { return 0 }
        return availableMemberBandWidth / CGFloat(memberCount)
    }

    /// Column width for layout + clipping — fixed band width when scrolling, else equal split.
    static func memberColumnWidth(
        memberCount: Int,
        fixedBandWidth: CGFloat,
        availableMemberBandWidth: CGFloat
    ) -> CGFloat {
        if usesSharedHorizontalScroll(memberCount: memberCount) {
            return fixedBandWidth
        }
        return flexibleMemberColumnWidth(
            memberCount: memberCount,
            availableMemberBandWidth: availableMemberBandWidth
        )
    }

    /// Total width of the member band content inside horizontal scroll.
    static func memberBandContentWidth(memberCount: Int, fixedBandWidth: CGFloat) -> CGFloat {
        CGFloat(memberCount) * fixedBandWidth
    }
}

@Observable
@MainActor
final class SeasonLedgerMemberScrollSync {
    var contentOffsetX: CGFloat = 0
}

private struct SeasonLedgerMemberBandWidthKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

/// Pinned table header (stays visible) + vertically scrolling body; horizontal scroll stays in sync when needed.
struct SeasonLedgerPinnedTable<HeaderLeading: View, HeaderMembers: View, Body: View>: View {
    let memberCount: Int
    let fixedMemberBandWidth: CGFloat
    let leadingWidth: CGFloat
    @ViewBuilder var headerLeading: () -> HeaderLeading
    @ViewBuilder var headerMembers: () -> HeaderMembers
    @ViewBuilder var bodyContent: () -> Body

    @State private var memberBandViewportWidth: CGFloat = 0
    @State private var scrollSync = SeasonLedgerMemberScrollSync()

    private var usesScroll: Bool {
        SeasonLedgerMemberTableLayout.usesSharedHorizontalScroll(memberCount: memberCount)
    }

    private var memberColumnWidth: CGFloat {
        SeasonLedgerMemberTableLayout.memberColumnWidth(
            memberCount: memberCount,
            fixedBandWidth: fixedMemberBandWidth,
            availableMemberBandWidth: memberBandViewportWidth
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            tableBand(leading: headerLeading, members: headerMembers)
                .background(PickemsColors.cardBackground)
                .overlay(alignment: .bottom) {
                    Divider().overlay(PickemsColors.hairline)
                }

            ScrollView(.vertical) {
                bodyContent()
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .background {
            GeometryReader { geo in
                Color.clear.preference(
                    key: SeasonLedgerMemberBandWidthKey.self,
                    value: max(0, geo.size.width - leadingWidth)
                )
            }
        }
        .onPreferenceChange(SeasonLedgerMemberBandWidthKey.self) { memberBandViewportWidth = $0 }
        .environment(\.seasonLedgerMemberColumnWidth, memberColumnWidth)
        .environment(\.seasonLedgerScrollSync, scrollSync)
        .environment(\.seasonLedgerMemberScrollsHorizontally, usesScroll)
        .environment(\.seasonLedgerFixedMemberBandWidth, fixedMemberBandWidth)
        .environment(\.seasonLedgerTableMemberCount, memberCount)
    }

    @ViewBuilder
    private func tableBand<Leading: View, Members: View>(
        @ViewBuilder leading: () -> Leading,
        @ViewBuilder members: () -> Members
    ) -> some View {
        HStack(alignment: .top, spacing: 0) {
            leading()
                .frame(width: leadingWidth, alignment: .leading)
            memberBand(members: members)
        }
    }

    @ViewBuilder
    private func memberBand<Members: View>(@ViewBuilder members: () -> Members) -> some View {
        let band = members()
        if usesScroll {
            SeasonLedgerSyncedHorizontalMemberScroll(
                contentWidth: SeasonLedgerMemberTableLayout.memberBandContentWidth(
                    memberCount: memberCount,
                    fixedBandWidth: fixedMemberBandWidth
                ),
                sync: scrollSync
            ) {
                band
            }
            .accessibilityIdentifier(SeasonLedgerMemberTableLayout.sharedMemberScrollAccessibilityId)
        } else {
            band
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// Horizontal member band that shares offset with other bands via `SeasonLedgerMemberScrollSync`.
struct SeasonLedgerSyncedHorizontalMemberScroll<Content: View>: View {
    let contentWidth: CGFloat
    let sync: SeasonLedgerMemberScrollSync
    @ViewBuilder var content: () -> Content

    @State private var scrollPosition = ScrollPosition(edge: .leading)
    @State private var isApplyingRemote = false
    @State private var localOffsetX: CGFloat = 0

    private static let scrollSyncEpsilon: CGFloat = 0.5

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            content()
                .frame(width: contentWidth, alignment: .leading)
        }
        .scrollPosition($scrollPosition)
        .onScrollGeometryChange(for: CGFloat.self) { geometry in
            geometry.contentOffset.x
        } action: { _, newX in
            let clamped = max(0, newX)
            localOffsetX = clamped
            guard !isApplyingRemote else { return }
            if abs(sync.contentOffsetX - clamped) >= Self.scrollSyncEpsilon {
                sync.contentOffsetX = clamped
            }
        }
        .onChange(of: sync.contentOffsetX) { _, newX in
            guard abs(localOffsetX - newX) >= Self.scrollSyncEpsilon else { return }
            isApplyingRemote = true
            var updated = scrollPosition
            updated.scrollTo(x: newX)
            scrollPosition = updated
            localOffsetX = newX
            Task { @MainActor in
                isApplyingRemote = false
            }
        }
    }
}

// MARK: - Environment

private struct SeasonLedgerMemberColumnWidthKey: EnvironmentKey {
    static let defaultValue: CGFloat = 0
}

private struct SeasonLedgerScrollSyncKey: EnvironmentKey {
    static let defaultValue: SeasonLedgerMemberScrollSync = MainActor.assumeIsolated {
        SeasonLedgerMemberScrollSync()
    }()
}

private struct SeasonLedgerMemberScrollsHorizontallyKey: EnvironmentKey {
    static let defaultValue = false
}

private struct SeasonLedgerFixedMemberBandWidthKey: EnvironmentKey {
    static let defaultValue: CGFloat = 44
}

private struct SeasonLedgerTableMemberCountKey: EnvironmentKey {
    static let defaultValue = 0
}

extension EnvironmentValues {
    var seasonLedgerMemberColumnWidth: CGFloat {
        get { self[SeasonLedgerMemberColumnWidthKey.self] }
        set { self[SeasonLedgerMemberColumnWidthKey.self] = newValue }
    }

    var seasonLedgerScrollSync: SeasonLedgerMemberScrollSync {
        get { self[SeasonLedgerScrollSyncKey.self] }
        set { self[SeasonLedgerScrollSyncKey.self] = newValue }
    }

    var seasonLedgerMemberScrollsHorizontally: Bool {
        get { self[SeasonLedgerMemberScrollsHorizontallyKey.self] }
        set { self[SeasonLedgerMemberScrollsHorizontallyKey.self] = newValue }
    }

    var seasonLedgerFixedMemberBandWidth: CGFloat {
        get { self[SeasonLedgerFixedMemberBandWidthKey.self] }
        set { self[SeasonLedgerFixedMemberBandWidthKey.self] = newValue }
    }

    var seasonLedgerTableMemberCount: Int {
        get { self[SeasonLedgerTableMemberCountKey.self] }
        set { self[SeasonLedgerTableMemberCountKey.self] = newValue }
    }
}

extension View {
    @ViewBuilder
    func seasonLedgerMemberCellWidth() -> some View {
        modifier(SeasonLedgerMemberCellWidthModifier())
    }
}

private struct SeasonLedgerMemberCellWidthModifier: ViewModifier {
    @Environment(\.seasonLedgerMemberScrollsHorizontally) private var scrollsHorizontally
    @Environment(\.seasonLedgerMemberColumnWidth) private var columnWidth
    @Environment(\.seasonLedgerFixedMemberBandWidth) private var fixedBandWidth

    func body(content: Content) -> some View {
        if scrollsHorizontally {
            content
                .frame(width: fixedBandWidth)
        } else if columnWidth > 0 {
            content
                .frame(width: columnWidth)
                .clipped()
        } else {
            content
                .frame(maxWidth: .infinity)
        }
    }
}

/// Row slice used inside the scrollable body; reuses the same horizontal sync as the pinned header.
struct SeasonLedgerTableBodyBand<Leading: View, Members: View>: View {
    let leadingWidth: CGFloat
    @ViewBuilder var leading: () -> Leading
    @ViewBuilder var members: () -> Members

    @Environment(\.seasonLedgerMemberScrollsHorizontally) private var scrollsHorizontally
    @Environment(\.seasonLedgerScrollSync) private var scrollSync
    @Environment(\.seasonLedgerTableMemberCount) private var memberCount
    @Environment(\.seasonLedgerFixedMemberBandWidth) private var fixedBandWidth

    var body: some View {
        let memberBand = members()
        return HStack(alignment: .top, spacing: 0) {
            leading()
                .frame(width: leadingWidth, alignment: .leading)
            if scrollsHorizontally {
                SeasonLedgerSyncedHorizontalMemberScroll(
                    contentWidth: SeasonLedgerMemberTableLayout.memberBandContentWidth(
                        memberCount: memberCount,
                        fixedBandWidth: fixedBandWidth
                    ),
                    sync: scrollSync
                ) {
                    memberBand
                }
            } else {
                memberBand
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}