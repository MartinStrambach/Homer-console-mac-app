import Foundation
@testable import HomerCore
@testable import HomerAgents
import Testing

@Suite("Homer schedules")
struct HomerScheduleTests {
	private func agent(_ name: String, cron nextRunAt: Double??) -> HomerAgent {
		HomerAgent(
			name: name,
			cron: nextRunAt.map { HomerAgent.Cron(expression: "* * * * *", timezone: "UTC", nextRunAt: $0) }
		)
	}

	@Test("only agents with a cron, soonest next run first, unknown next runs last")
	func sortsByNextRun() {
		let agents = [
			agent("a-unscheduled", cron: .none),
			agent("b-later", cron: 2000),
			agent("c-no-next-run", cron: .some(nil)),
			agent("d-soon", cron: 1000),
			agent("e-later-too", cron: 2000),
			agent("f-no-next-run", cron: .some(nil)),
		]

		#expect(HomerAgent.schedules(agents).map(\.name) == [
			"d-soon",
			// Ties keep the list's order.
			"b-later",
			"e-later-too",
			"c-no-next-run",
			"f-no-next-run",
		])
	}

	@Test("the countdown reads as the console's formatTimeUntil")
	func countdown() {
		let now = Date(timeIntervalSince1970: 1_000_000)
		#expect(HomerFormat.timeUntil(1_000_000 + 2 * 3600 + 3 * 60 + 5, now: now) == "in 2h 3m")
		#expect(HomerFormat.timeUntil(1_000_000 + 26 * 3600, now: now) == "in 1d 2h")
		#expect(HomerFormat.timeUntil(1_000_000 + 45, now: now) == "in 45s")
		#expect(HomerFormat.timeUntil(1_000_000, now: now) == "expired")
	}

	@Test(
		"a cron in words",
		arguments: [
			("* * * * *", "Every minute"),
			("*/15 * * * *", "Every 15 minutes"),
			("*/1 * * * *", "Every minute"),
			("4-59/10 * * * *", "Every 10 minutes from :04"),
			("4/10 * * * *", "Every 10 minutes from :04"),
			("0-59/20 * * * *", "Every 20 minutes"),
			("5-35/10 * * * *", "Every 10 minutes from :05 to :35"),
			("4-59/10 * * * 1-5", "Every 10 minutes from :04, weekdays"),
			("0 * * * *", "Every hour"),
			("30 * * * *", "Every hour at :30"),
			("5 */2 * * *", "Every 2 hours at :05"),
			("0 9-17 * * 1-5", "Every hour from 09:00 to 17:00, weekdays"),
			("0 9 * * *", "Every day at 09:00"),
			("0,30 9 * * *", "Every day at 09:00 and 09:30"),
			("0 9,13,17 * * *", "Every day at 09:00, 13:00 and 17:00"),
			("0 9 * * 1-5", "Weekdays at 09:00"),
			("0 9 * * MON-FRI", "Weekdays at 09:00"),
			("0 10 * * 6,0", "Weekends at 10:00"),
			("0 9 * * 1", "Every Monday at 09:00"),
			("0 9 * * 1,5", "Every Monday and Friday at 09:00"),
			("0 9 * * 1-3", "Monday to Wednesday at 09:00"),
			("0 9 * * 5-7", "Friday to Sunday at 09:00"),
			("0 9 * * 0-6", "Every day at 09:00"),
			("*/10 * * * 1,3", "Every 10 minutes on Monday and Wednesday"),
			("0 6 1 * *", "Monthly on the 1st at 06:00"),
			("0 6 1,15 * *", "Monthly on the 1st and 15th at 06:00"),
			("0 * 2 * *", "Every hour on the 2nd of the month"),
			("0 0 25 dec *", "Every year on December 25 at 00:00"),
			("@daily", "Every day at 00:00"),
			("@weekly", "Every Sunday at 00:00"),
			("@hourly", "Every hour"),
		]
	)
	func summary(expression: String, expected: String) {
		#expect(HomerAgent.Cron(expression: expression, timezone: "UTC").summary == expected)
	}

	@Test(
		"a cron it cannot put in words has no summary",
		arguments: ["0 9 L * *", "0 9 * * 1#2", "0 9-17/2 * * *", "*/5 9 * * *", "4-59/10 9 * * *", "59-4/10 * * * *", "0 0 9 * * *", "0 9 1 * 1", "nonsense"]
	)
	func noSummary(expression: String) {
		#expect(HomerAgent.Cron(expression: expression, timezone: "UTC").summary == nil)
	}

	@Test("the bar fills from the last run to the next")
	func progress() {
		let cron = HomerAgent.Cron(expression: "* * * * *", timezone: "UTC", nextRunAt: 2000, lastRunAt: 1000)
		#expect(cron.progress(at: Date(timeIntervalSince1970: 1250)) == 0.25)
		#expect(cron.progress(at: Date(timeIntervalSince1970: 500)) == 0)
		#expect(cron.progress(at: Date(timeIntervalSince1970: 3000)) == 1)
		#expect(HomerAgent.Cron(expression: "* * * * *", timezone: "UTC", nextRunAt: 2000).progress(at: .now) == nil)
	}

	@Test("time since the last run")
	func timeSince() {
		let now = Date(timeIntervalSince1970: 1_000_000)
		#expect(HomerScheduleFormat.timeSince(1_000_000 - (2 * 3600 + 3 * 60 + 5), now: now) == "2h 3m ago")
		#expect(HomerScheduleFormat.timeSince(1_000_000 - 26 * 3600, now: now) == "1d 2h ago")
		#expect(HomerScheduleFormat.timeSince(1_000_000 - 45, now: now) == "45s ago")
		#expect(HomerScheduleFormat.timeSince(1_000_000, now: now) == "just now")
	}
}
