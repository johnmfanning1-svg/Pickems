import Foundation
import Testing
@testable import Pickems

struct TeamThemeCatalogTests {
    @Test func resolvesAlabamaPalette() {
        let palette = TeamThemeCatalog.palette(for: "333")
        #expect(palette.favoriteTeamId == "333")
        #expect(palette.favoriteTeamName == "Alabama")
        #expect(palette.favoriteTeamAbbreviation == "ALA")
        #expect(palette.favoriteTeamLogoURL?.contains("333") == true)
    }

    @Test func unknownTeamFallsBackToDefault() {
        let palette = TeamThemeCatalog.palette(for: "not-a-team")
        #expect(palette == .pickemsDefault)
        #expect(palette.favoriteTeamId == nil)
    }

    @Test func nilTeamFallsBackToDefault() {
        #expect(TeamThemeCatalog.palette(for: String?.none) == .pickemsDefault)
    }

    @Test func searchMatchesNameAndAbbreviation() {
        let byName = TeamThemeCatalog.team(matching: "ohio")
        #expect(byName.contains(where: { $0.id == "194" }))

        let byAbbr = TeamThemeCatalog.team(matching: "ALA")
        #expect(byAbbr.contains(where: { $0.abbreviation == "ALA" }))
    }

    @Test func catalogHasUniqueIds() {
        let ids = TeamThemeCatalog.sortedTeams.map(\.id)
        #expect(Set(ids).count == ids.count)
    }

    @Test func profileFavoriteTeamResolvesFromCatalog() {
        var profile = UserProfile(
            id: "u1",
            displayName: "Alex",
            avatarColorHex: "#DC2626",
            avatarImageURL: nil,
            createdAt: Date()
        )
        profile.favoriteTeamId = "194"
        #expect(profile.favoriteTeam?.name == "Ohio State")
        #expect(TeamThemeCatalog.palette(for: profile).favoriteTeamAbbreviation == "OSU")
    }

    @Test func auburnAccentPrefersReadableOrangeOverNavy() {
        let team = TeamThemeCatalog.team(id: "2")
        #expect(team?.name == "Auburn")
        let palette = TeamThemeCatalog.palette(for: "2")
        let background = ColorContrast.appBackground
        let navy = ColorContrast.RGB.from(hex: "#0C2340")
        let orange = ColorContrast.RGB.from(hex: "#E87722")
        let chosen = ColorContrast.accessibleAccent(candidates: [navy, orange], against: background)

        #expect(ColorContrast.contrastRatio(navy, background) < 4.5)
        #expect(ColorContrast.contrastRatio(chosen, background) >= 4.5)
        // Orange already clears the bar, so it should win over lightened navy.
        #expect(chosen.hex == orange.hex)
        #expect(palette.favoriteTeamId == "2")
        #expect(ColorContrast.contrastRatio(
            ColorContrast.onAccent(for: chosen),
            chosen
        ) >= 4.5)
    }

    @Test func everyCatalogTeamProducesReadableAccent() {
        let background = ColorContrast.appBackground
        for team in TeamThemeCatalog.sortedTeams {
            let primary = ColorContrast.RGB.from(hex: team.primaryHex)
            let secondary = ColorContrast.RGB.from(hex: team.secondaryHex)
            let accent = ColorContrast.accessibleAccent(
                candidates: [primary, secondary],
                against: background
            )
            let onAccent = ColorContrast.onAccent(for: accent)
            #expect(
                ColorContrast.contrastRatio(accent, background) >= 4.5,
                "\(team.name) accent \(accent.hex) must read on dark UI"
            )
            #expect(
                ColorContrast.contrastRatio(onAccent, accent) >= 4.5,
                "\(team.name) onAccent must read on accent fill \(accent.hex)"
            )
        }
    }

    @Test func darkPrimaryTeamsMeetAccentContrast() {
        // Auburn, Michigan, Penn State, Notre Dame — dark primaries that fail raw on black.
        for teamId in ["2", "130", "213", "87"] {
            let team = try #require(TeamThemeCatalog.team(id: teamId))
            let background = ColorContrast.appBackground
            let primary = ColorContrast.RGB.from(hex: team.primaryHex)
            let secondary = ColorContrast.RGB.from(hex: team.secondaryHex)
            let accent = ColorContrast.accessibleAccent(
                candidates: [primary, secondary],
                against: background
            )
            #expect(
                ColorContrast.contrastRatio(accent, background) >= 4.5,
                "\(team.name) accent \(accent.hex) must read on dark UI"
            )
        }
    }

    @Test func lightAccentFillsGetDarkOnAccent() {
        let gold = ColorContrast.RGB.from(hex: "#FFCD00")
        let onGold = ColorContrast.onAccent(for: gold)
        #expect(ColorContrast.contrastRatio(onGold, gold) >= 4.5)
        #expect(onGold.luminance < 0.5)
    }
}

struct SeasonCloseEngineTests {
    private func member(
        id: String,
        name: String,
        wins: Int,
        losses: Int
    ) -> GroupMember {
        GroupMember(
            id: id,
            displayName: name,
            avatarColorHex: "#111111",
            role: .member,
            joinedAt: Date(timeIntervalSince1970: 0),
            seasonWins: wins,
            seasonLosses: losses
        )
    }

    @Test func ranksByWinsThenBattingAverage() {
        let members = [
            member(id: "a", name: "Alex", wins: 10, losses: 5),
            member(id: "b", name: "Blake", wins: 12, losses: 3),
            member(id: "c", name: "Casey", wins: 10, losses: 2),
        ]

        let standings = SeasonCloseEngine.finalStandings(from: members)
        #expect(standings.map(\.id) == ["b", "c", "a"])
        #expect(standings.map(\.rank) == [1, 2, 3])
        #expect(standings.first?.seasonWins == 12)
    }

    @Test func makeArchiveSetsChampionAndWeekCount() {
        let members = [
            member(id: "a", name: "Alex", wins: 8, losses: 4),
            member(id: "b", name: "Blake", wins: 11, losses: 1),
        ]
        let archive = SeasonCloseEngine.makeArchive(
            seasonYear: 2025,
            groupId: "g1",
            members: members,
            weekCount: 14
        )

        #expect(archive.id == "2025")
        #expect(archive.seasonYear == 2025)
        #expect(archive.championUserId == "b")
        #expect(archive.championDisplayName == "Blake")
        #expect(archive.weekCount == 14)
        #expect(archive.finalStandings.count == 2)
    }

    @Test func updatedCareerAccumulatesTitlesAndRecords() {
        let member = member(id: "a", name: "Alex", wins: 10, losses: 4)
        let first = SeasonCloseEngine.updatedCareer(
            existing: nil,
            member: member,
            finish: 1,
            wonTitle: true,
            now: Date(timeIntervalSince1970: 100)
        )
        #expect(first.titles == 1)
        #expect(first.seasonWins == 10)
        #expect(first.seasonLosses == 4)
        #expect(first.seasonsPlayed == 1)
        #expect(first.bestFinish == 1)

        let nextSeason = GroupMember(
            id: "a",
            displayName: "Alex",
            avatarColorHex: "#111111",
            role: .member,
            joinedAt: Date(timeIntervalSince1970: 0),
            seasonWins: 7,
            seasonLosses: 7
        )
        let second = SeasonCloseEngine.updatedCareer(
            existing: first,
            member: nextSeason,
            finish: 3,
            wonTitle: false,
            now: Date(timeIntervalSince1970: 200)
        )
        #expect(second.titles == 1)
        #expect(second.seasonWins == 17)
        #expect(second.seasonLosses == 11)
        #expect(second.seasonsPlayed == 2)
        #expect(second.bestFinish == 1)
    }

    @Test func bestFinishImprovesWhenLowerRankAchieved() {
        let existing = CareerRecord(
            id: "a",
            displayName: "Alex",
            avatarColorHex: "#111111",
            titles: 0,
            seasonWins: 5,
            seasonLosses: 5,
            seasonsPlayed: 1,
            bestFinish: 4,
            updatedAt: Date(timeIntervalSince1970: 1)
        )
        let member = member(id: "a", name: "Alex", wins: 9, losses: 3)
        let updated = SeasonCloseEngine.updatedCareer(
            existing: existing,
            member: member,
            finish: 2,
            wonTitle: false
        )
        #expect(updated.bestFinish == 2)
    }
}
