import XCTest
@testable import PrefrontalCortex

final class DeviationStoreTests: XCTestCase {
    func test_today_workouts_filters_out_yesterday() throws {
        let cal = Calendar.current
        let today     = cal.startOfDay(for: Date())
        let yesterday = cal.date(byAdding: .day, value: -1, to: today)!
        let rows = [
            DeviationStore.TodayWorkout(sport: "Cycling", durationMin: 30, date: yesterday),
            DeviationStore.TodayWorkout(sport: "Running", durationMin: 15, date: today),
        ]
        DeviationStore.setTodayWorkouts(rows)
        let result = DeviationStore.todayWorkouts()
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.sport, "Running")
    }
}
