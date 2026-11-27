import Testing
@testable import Pickems

struct PickemsWeekSortTests {
    @Test func bowlWeeksSortAfterWeekFifteen() {
        let w2 = PickemsWeekSort.rank(seasonYear: 2026, weekId: "2026-W2", weekNumber: 2)
        let w15 = PickemsWeekSort.rank(seasonYear: 2026, weekId: "2026-W15", weekNumber: 15)
        let bowl1 = PickemsWeekSort.rank(seasonYear: 2026, weekId: "2026-BOWL1", weekNumber: 1)
        let bowl2 = PickemsWeekSort.rank(seasonYear: 2026, weekId: "2026-BOWL2", weekNumber: 2)
        #expect(w2.ordinal < w15.ordinal)
        #expect(w15.ordinal < bowl1.ordinal)
        #expect(bowl1.ordinal < bowl2.ordinal)
    }
}