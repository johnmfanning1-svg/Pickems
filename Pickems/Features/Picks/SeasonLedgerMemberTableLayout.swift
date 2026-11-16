import SwiftUI

/// Split table: pinned leading column + one shared horizontal scroll for all member columns.
enum SeasonLedgerMemberTableLayout {
    /// Members beyond this count share a single horizontal `ScrollView` for every row band.
    static let sharedScrollMemberThreshold = 4

    static func usesSharedHorizontalScroll(memberCount: Int) -> Bool {
        memberCount > sharedScrollMemberThreshold
    }

    static var sharedMemberScrollAccessibilityId: String { "seasonLedger.sharedMemberScroll" }
}

struct SeasonLedgerSplitMemberScroll<Leading: View, MemberBand: View>: View {
    let memberCount: Int
    let memberBandWidth: CGFloat
    let leadingWidth: CGFloat
    let rowSpacing: CGFloat
    @ViewBuilder var leading: () -> Leading
    @ViewBuilder var memberBand: () -> MemberBand

    private var usesScroll: Bool {
        SeasonLedgerMemberTableLayout.usesSharedHorizontalScroll(memberCount: memberCount)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            leading()
                .frame(width: leadingWidth, alignment: .leading)
            if usesScroll {
                ScrollView(.horizontal, showsIndicators: false) {
                    memberBand()
                        .frame(
                            width: CGFloat(memberCount) * memberBandWidth,
                            alignment: .leading
                        )
                }
                .accessibilityIdentifier(SeasonLedgerMemberTableLayout.sharedMemberScrollAccessibilityId)
            } else {
                memberBand()
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}