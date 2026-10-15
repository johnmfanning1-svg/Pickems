import Foundation
import SwiftUI
import Testing
import UIKit
@testable import Pickems

struct SelectionVetoTests {
    private let now = Date(timeIntervalSince1970: 1_759_000_000)

    @Test func vetoDefaultsOffAndNeedsTwoVotes() {
        let rules = GroupRules.default
        #expect(rules.vetoEnabled == false)
        #expect(rules.vetoVotesNeeded == 2)
        #expect(SelectionVetoPolicy.defaultVotesNeeded == 2)
    }

    @Test func missingStoredFieldsStayOff() throws {
        let json = """
        {
          "selectionMode": "member",
          "selectionsPerMember": 3,
          "slateSize": 12,
          "pickDeadline": "firstKickoff",
          "tieBreaker": "commissionerOverride"
        }
        """.data(using: .utf8)!
        let rules = try JSONDecoder().decode(GroupRules.self, from: json)
        #expect(rules.vetoEnabled == false)
        #expect(rules.vetoVotesNeeded == 2)
    }

    @Test func commissionerVotesNeededRoundTripsAndClamps() throws {
        var rules = GroupRules.default
        rules.vetoEnabled = true
        rules.vetoVotesNeeded = 3
        let data = try JSONEncoder().encode(rules)
        let decoded = try JSONDecoder().decode(GroupRules.self, from: data)
        #expect(decoded.vetoEnabled == true)
        #expect(decoded.vetoVotesNeeded == 3)
        #expect(SelectionVetoPolicy.clampedVotesNeeded(1, memberCount: 5) == 1)
        #expect(SelectionVetoPolicy.clampedVotesNeeded(9, memberCount: 5) == 4)
    }

    @Test func votesNeededCapsAtOneLessThanLeagueSize() {
        #expect(SelectionVetoPolicy.maxVotesNeeded(memberCount: 1) == 0)
        #expect(SelectionVetoPolicy.maxVotesNeeded(memberCount: 5) == 4)
        #expect(!SelectionVetoPolicy.canConfigure(memberCount: 1))
        #expect(SelectionVetoPolicy.canConfigure(memberCount: 2))
        #expect(SelectionVetoPolicy.clampedVotesNeeded(2, memberCount: 8) == 2)
        #expect(SelectionVetoPolicy.clampedVotesNeeded(9, memberCount: 4) == 3)
        #expect(SelectionVetoPolicy.clampedVotesNeeded(2, memberCount: 2) == 1)
        #expect(SelectionVetoPolicy.clampedVotesNeeded(0, memberCount: 6) == 2)
        #expect(SelectionVetoPolicy.clampedVotesNeeded(4, memberCount: 1) == 4)
    }

    @Test func onlyAnotherMemberCanVoteWhileSelectionsAreOpen() {
        let kickoff = now.addingTimeInterval(60 * 60)
        #expect(
            SelectionVetoPolicy.canVote(
                vetoEnabled: true,
                isOwnSelection: false,
                selectionsOpen: true,
                kickoff: kickoff,
                now: now
            )
        )
        #expect(
            !SelectionVetoPolicy.canVote(
                vetoEnabled: false,
                isOwnSelection: false,
                selectionsOpen: true,
                kickoff: kickoff,
                now: now
            )
        )
        #expect(
            !SelectionVetoPolicy.canVote(
                vetoEnabled: true,
                isOwnSelection: true,
                selectionsOpen: true,
                kickoff: kickoff,
                now: now
            )
        )
        #expect(
            !SelectionVetoPolicy.canVote(
                vetoEnabled: true,
                isOwnSelection: false,
                selectionsOpen: false,
                kickoff: kickoff,
                now: now
            )
        )
        #expect(
            !SelectionVetoPolicy.canVote(
                vetoEnabled: true,
                isOwnSelection: false,
                selectionsOpen: true,
                kickoff: now,
                now: now
            )
        )
    }

    @Test func aVetoBlocksThatMemberFromTheSameGame() {
        let veto = SelectionVeto(
            id: "selector_401",
            submittedBy: "selector",
            submitterName: "Sam",
            espnEventId: "401",
            awayTeamName: "Alabama",
            awayTeamAbbreviation: "ALA",
            homeTeamName: "Georgia",
            homeTeamAbbreviation: "UGA",
            voteCount: 2,
            votesNeeded: 2
        )
        #expect(SelectionVetoPolicy.blockedEventIds(vetoes: [veto], userId: "selector") == ["401"])
        #expect(SelectionVetoPolicy.blockedEventIds(vetoes: [veto], userId: "other").isEmpty)
        #expect(veto.matchupLabel == "ALA @ UGA")
    }

    @Test func settingsFooterNamesTheCap() {
        #expect(SelectionVetoPolicy.settingsFooter(memberCount: 4).contains("3"))
        #expect(SelectionVetoPolicy.settingsFooter(memberCount: 1).contains("one other member"))
    }

    @Test func selectionVetoPushOpensThatGame() {
        let action = DeepLinkRouter.parseNotification(userInfo: [
            "type": "selection_veto",
            "groupId": "group-1",
            "weekId": "2026-W6",
            "gameId": "401",
            "deepLink": "pickems://league/group-1/week/2026-W6/game/401",
        ])
        #expect(action == .openGame(groupId: "group-1", weekId: "2026-W6", gameId: "401"))
        #expect(
            NotificationLaunch.resolve(
                action: action!,
                groupsLoaded: true,
                memberGroupIds: ["group-1"]
            ) == .pickems(groupId: "group-1", weekId: "2026-W6", gameId: "401")
        )
    }

    @Test func selectionVetoUsesTheSelectionDeadlinePreference() {
        #expect(NotificationPrefCategory.selectionDeadlines.pushTypes.contains("selection_veto"))
        let others = NotificationPrefCategory.allCases.filter { $0 != .selectionDeadlines }
        #expect(others.allSatisfy { !$0.pushTypes.contains("selection_veto") })
    }

    @Test func vetoConfirmNamesTheGameAndKeepsASeparateAnchorPerRow() {
        #expect(SelectionVetoPrompt.title == "Veto this Selection?")
        #expect(
            SelectionVetoPrompt.message(matchup: "#4 OSU @ #5 IU", votesNeeded: 2)
                == "#4 OSU @ #5 IU is removed if 2 members vote before kickoff. You can't take this vote back."
        )
        let ids = (1...5).map { SelectionVetoPrompt.anchorIdentifier(nominationId: "nom-\($0)") }
        #expect(Set(ids).count == ids.count)
        #expect(ids[4] == "selection-veto-nom-5")
        #expect(!ids.contains("member-header"))
    }

    @MainActor
    @Test func fifthRowVetoPopoverAnchorsToThatButton() throws {
        let header = UIView(frame: CGRect(x: 0, y: 0, width: 390, height: 64))
        header.accessibilityIdentifier = "member-header"
        let rows: [(id: String, matchup: String, y: CGFloat)] = [
            ("n1", "#1 ALA @ AUB", 80),
            ("n2", "#2 UGA @ TEN", 160),
            ("n3", "#3 TEX @ OU", 240),
            ("n4", "#6 PSU @ #7 ORE", 320),
            ("n5", "#4 OSU @ #5 IU", 480),
        ]
        let container = UIView(frame: CGRect(x: 0, y: 0, width: 390, height: 700))
        container.addSubview(header)
        let anchors = rows.map { row in
            let anchor = SelectionVetoConfirmAnchorView(
                frame: CGRect(x: 220, y: row.y, width: 72, height: 30)
            )
            anchor.promptMessage = SelectionVetoPrompt.message(matchup: row.matchup, votesNeeded: 2)
            anchor.accessibilityIdentifier = SelectionVetoPrompt.anchorIdentifier(nominationId: row.id)
            container.addSubview(anchor)
            return anchor
        }
        let fifth = try #require(anchors.last)
        let alert = fifth.makeAlert()
        let popover = try #require(alert.popoverPresentationController)
        let sourceId = popover.sourceView.map(ObjectIdentifier.init)

        #expect(alert.title == "Veto this Selection?")
        #expect(
            alert.message
                == "#4 OSU @ #5 IU is removed if 2 members vote before kickoff. You can't take this vote back."
        )
        #expect(sourceId == ObjectIdentifier(fifth))
        #expect(popover.sourceRect == fifth.bounds)
        #expect(popover.sourceRect == CGRect(x: 0, y: 0, width: 72, height: 30))
        #expect(sourceId != ObjectIdentifier(header))
        #expect(sourceId != ObjectIdentifier(container))
        #expect(sourceId != ObjectIdentifier(anchors[0]))
        #expect(alert.modalPresentationStyle == .popover)
        #expect(popover.permittedArrowDirections.contains(.up))
        #expect(popover.permittedArrowDirections.contains(.down))
        #expect(alert.actions.contains { $0.title == "Veto" && $0.style == .destructive })
        #expect(alert.actions.contains { $0.title == "Cancel" && $0.style == .cancel })
        let presentation = UIPresentationController(
            presentedViewController: UIViewController(),
            presenting: UIViewController()
        )
        let adapted = popover.delegate?.adaptivePresentationStyle?(
            for: presentation,
            traitCollection: UITraitCollection(horizontalSizeClass: .compact)
        )
        #expect(adapted == UIModalPresentationStyle.none)

        let sources = Set(anchors.compactMap { anchor -> ObjectIdentifier? in
            guard let view = anchor.makeAlert().popoverPresentationController?.sourceView else { return nil }
            return ObjectIdentifier(view)
        })
        #expect(sources.count == anchors.count)
    }
}

/// Renders a member header plus five Veto buttons and checks the 5th row's
/// confirmation source sits on that button, below the header.
@MainActor
struct SelectionVetoAnchorUITests {
    @Test func fifthSelectionButtonAnchorsItsOwnPopover() async throws {
        let rows = [
            VetoAnchorFixture(id: "n1", matchup: "#1 ALA @ AUB"),
            VetoAnchorFixture(id: "n2", matchup: "#2 UGA @ TEN"),
            VetoAnchorFixture(id: "n3", matchup: "#3 TEX @ OU"),
            VetoAnchorFixture(id: "n4", matchup: "#6 PSU @ #7 ORE"),
            VetoAnchorFixture(id: "n5", matchup: "#4 OSU @ #5 IU"),
        ]
        let host = UIHostingController(rootView: SelectionVetoAnchorHarness(rows: rows))
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        let window = scene.map { UIWindow(windowScene: $0) } ?? UIWindow()
        window.frame = CGRect(x: 0, y: 0, width: 393, height: 852)
        let previousKey = scene?.windows.first { $0.isKeyWindow }
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            window.rootViewController = nil
            if let previousKey, previousKey !== window {
                previousKey.makeKeyAndVisible()
            }
        }

        host.view.frame = window.bounds
        let fifthId = SelectionVetoPrompt.anchorIdentifier(nominationId: "n5")
        var anchors: [SelectionVetoConfirmAnchorView] = []
        for _ in 0..<20 {
            host.view.setNeedsLayout()
            host.view.layoutIfNeeded()
            anchors = vetoAnchorViews(in: host.view)
            if anchors.count == rows.count,
               anchors.contains(where: { $0.accessibilityIdentifier == fifthId }) {
                break
            }
            try await Task.sleep(nanoseconds: 50_000_000)
        }

        try #require(anchors.count == rows.count)
        let fifth = try #require(anchors.first { $0.accessibilityIdentifier == fifthId })
        let first = try #require(anchors.first {
            $0.accessibilityIdentifier == SelectionVetoPrompt.anchorIdentifier(nominationId: "n1")
        })
        #expect(fifth.bounds.width > 1)
        #expect(fifth.bounds.height > 1)
        let fifthY = fifth.convert(fifth.bounds, to: nil).minY
        let firstY = first.convert(first.bounds, to: nil).minY
        #expect(fifthY > firstY)

        let alert = fifth.makeAlert()
        #expect(alert.popoverPresentationController?.sourceView.map(ObjectIdentifier.init) == ObjectIdentifier(fifth))
        #expect(
            alert.message
                == "#4 OSU @ #5 IU is removed if 2 members vote before kickoff. You can't take this vote back."
        )
    }

    @Test func reorderingRowsConfirmsTheTappedSelection() async throws {
        let model = VetoReorderModel(rows: [
            VetoAnchorFixture(id: "n1", matchup: "#1 ALA @ AUB"),
            VetoAnchorFixture(id: "n2", matchup: "#2 UGA @ TEN"),
            VetoAnchorFixture(id: "n3", matchup: "#3 TEX @ OU"),
            VetoAnchorFixture(id: "n4", matchup: "#6 PSU @ #7 ORE"),
            VetoAnchorFixture(id: "n5", matchup: "#4 OSU @ #5 IU"),
        ])
        let host = UIHostingController(rootView: SelectionVetoReorderHarness(model: model))
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        let window = scene.map { UIWindow(windowScene: $0) } ?? UIWindow()
        window.frame = CGRect(x: 0, y: 0, width: 393, height: 852)
        let previousKey = scene?.windows.first { $0.isKeyWindow }
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer {
            host.dismiss(animated: false)
            window.isHidden = true
            window.rootViewController = nil
            if let previousKey, previousKey !== window {
                previousKey.makeKeyAndVisible()
            }
        }
        host.view.frame = window.bounds

        _ = try await waitForVetoAnchors(in: host.view, count: model.rows.count)
        model.rows.reverse()

        let topId = SelectionVetoPrompt.anchorIdentifier(nominationId: "n5")
        var top: SelectionVetoConfirmAnchorView?
        for _ in 0..<20 {
            host.view.setNeedsLayout()
            host.view.layoutIfNeeded()
            let anchors = vetoAnchorViews(in: host.view)
            top = anchors.min {
                $0.convert($0.bounds, to: nil).minY < $1.convert($1.bounds, to: nil).minY
            }
            if anchors.count == model.rows.count, top?.accessibilityIdentifier == topId {
                break
            }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        let tapped = try #require(top)
        #expect(tapped.accessibilityIdentifier == topId)
        #expect(tapRow(tapped, in: host.view))

        var alert = presentedAlert(in: window)
        if alert == nil {
            try await Task.sleep(nanoseconds: 150_000_000)
            alert = presentedAlert(in: window)
        }
        let confirmation = try #require(alert)
        #expect(
            confirmation.message
                == "#4 OSU @ #5 IU is removed if 2 members vote before kickoff. You can't take this vote back."
        )
        #expect(model.confirmed.isEmpty)
        #expect(SelectionVetoPrompt.performVeto(on: confirmation))
        for _ in 0..<20 where model.confirmed.isEmpty {
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        #expect(model.confirmed == ["n5"])
    }
}

private struct VetoAnchorFixture: Identifiable {
    let id: String
    let matchup: String
}

@MainActor
@Observable
private final class VetoReorderModel {
    var rows: [VetoAnchorFixture]
    var confirmed: [String] = []

    init(rows: [VetoAnchorFixture]) {
        self.rows = rows
    }
}

private struct SelectionVetoReorderHarness: View {
    @Bindable var model: VetoReorderModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Button("Alex") {}
                .accessibilityIdentifier("member-header")
            ForEach(model.rows) { row in
                SelectionVetoButton(
                    nominationId: row.id,
                    matchup: row.matchup,
                    votesNeeded: 2,
                    voted: false,
                    onConfirm: { model.confirmed.append(row.id) }
                )
            }
        }
        .padding()
        .frame(width: 393, alignment: .leading)
        .environment(\.themePalette, .pickemsDefault)
    }
}

private struct SelectionVetoAnchorHarness: View {
    let rows: [VetoAnchorFixture]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Button("Alex") {}
                .accessibilityIdentifier("member-header")
            ForEach(rows) { row in
                SelectionVetoButton(
                    nominationId: row.id,
                    matchup: row.matchup,
                    votesNeeded: 2,
                    voted: false,
                    onConfirm: {}
                )
            }
        }
        .padding()
        .frame(width: 393, alignment: .leading)
        .environment(\.themePalette, .pickemsDefault)
    }
}

@MainActor
private func waitForVetoAnchors(in root: UIView, count: Int) async throws -> [SelectionVetoConfirmAnchorView] {
    var anchors: [SelectionVetoConfirmAnchorView] = []
    for _ in 0..<20 {
        root.setNeedsLayout()
        root.layoutIfNeeded()
        anchors = vetoAnchorViews(in: root)
        if anchors.count == count { return anchors }
        try await Task.sleep(nanoseconds: 50_000_000)
    }
    try #require(anchors.count == count)
    return anchors
}

/// Taps the Veto control for this row. The anchor is that control; the visible SwiftUI
/// button is the fallback when the identifier is installed on a different view.
@MainActor
private func tapRow(_ anchor: UIView, in root: UIView) -> Bool {
    if activate(anchor) { return true }
    let buttonId = anchor.accessibilityIdentifier.map {
        $0.replacingOccurrences(of: "selection-veto-", with: "selection-veto-button-")
    }
    if let buttonId,
       let button = uiViews(in: root).first(where: { $0.accessibilityIdentifier == buttonId }) {
        if activate(button) { return true }
    }
    var current = anchor.superview
    while let candidate = current {
        if activate(candidate) { return true }
        current = candidate.superview
    }
    return false
}

@MainActor
private func activate(_ view: UIView) -> Bool {
    if let control = view as? UIControl {
        control.sendActions(for: .touchUpInside)
        return true
    }
    return view.accessibilityActivate()
}

private func presentedAlert(in window: UIWindow) -> UIAlertController? {
    var controller = window.rootViewController
    while let presented = controller?.presentedViewController {
        controller = presented
    }
    return controller as? UIAlertController
}

private func uiViews(in view: UIView) -> [UIView] {
    view.subviews.reduce(into: [view]) { result, child in
        result.append(contentsOf: uiViews(in: child))
    }
}

private func vetoAnchorViews(in view: UIView) -> [SelectionVetoConfirmAnchorView] {
    uiViews(in: view).compactMap { $0 as? SelectionVetoConfirmAnchorView }
}
