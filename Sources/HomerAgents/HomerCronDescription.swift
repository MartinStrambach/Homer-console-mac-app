import Foundation

extension HomerAgent.Cron {
	/// The expression in words — "Every day at 09:00", "Every 15 minutes on weekdays" — for the
	/// common shapes of a five-field cron, nil for any other (the page then shows the expression
	/// alone). Times are the cron's own, in its timezone.
	var summary: String? {
		HomerCronDescription.describe(expression)
	}

	/// How far along it is from the last run to the next, 0 to 1 — nil unless both are known and
	/// the next comes after the last.
	func progress(at now: Date) -> Double? {
		guard let lastRunAt, let nextRunAt, nextRunAt > lastRunAt else {
			return nil
		}
		let elapsed = now.timeIntervalSince1970 - lastRunAt
		return min(max(elapsed / (nextRunAt - lastRunAt), 0), 1)
	}
}

/// Five-field crons in words. Only what reads unambiguously in a sentence is described: numbers,
/// lists, `*/n` steps (in the minutes also `a/n` and `a-b/n`), an hour range and day-of-week
/// ranges (names or numbers); anything else — `L`, `W`, `#`, stepped hour ranges, a sixth field —
/// gets nil.
nonisolated enum HomerCronDescription {
	static func describe(_ expression: String) -> String? {
		let expression = expression.trimmingCharacters(in: .whitespaces).lowercased()
		if let expanded = macros[expression] {
			return describe(expanded)
		}
		let fields = expression.split(whereSeparator: \.isWhitespace).map(String.init)
		guard fields.count == 5,
		      let time = time(minute: fields[0], hour: fields[1]),
		      let days = days(dayOfMonth: fields[2], month: fields[3], dayOfWeek: fields[4])
		else {
			return nil
		}
		return sentence(time, days)
	}

	private static let macros = [
		"@yearly": "0 0 1 1 *",
		"@annually": "0 0 1 1 *",
		"@monthly": "0 0 1 * *",
		"@weekly": "0 0 * * 0",
		"@daily": "0 0 * * *",
		"@midnight": "0 0 * * *",
		"@hourly": "0 * * * *",
	]

	// MARK: - Time of day

	private enum Time {
		/// Fixed times of day, "09:00".
		case at([String])
		/// A repetition through the day, "Every 15 minutes".
		case every(String)
	}

	private static func time(minute: String, hour: String) -> Time? {
		if minute == "*" {
			return hour == "*" ? .every("Every minute") : nil
		}
		if let (step, first, last) = steps(minute, in: 0 ... 59) {
			guard hour == "*" else {
				return nil
			}
			let every = step == 1 ? "Every minute" : "Every \(step) minutes"
			// Through the end of the hour when no further step would fit before it.
			let toEnd = last + step > 59
			return switch (first, toEnd) {
			case (0, true): .every(every)
			case (_, true): .every("\(every) from :\(twoDigits(first))")
			case (_, false): .every("\(every) from :\(twoDigits(first)) to :\(twoDigits(last))")
			}
		}
		guard let minutes = numbers(minute, in: 0 ... 59) else {
			return nil
		}
		if hour == "*" || step(hour, in: 0 ... 23) != nil {
			guard minutes.count == 1 else {
				return nil
			}
			let every = step(hour, in: 0 ... 23).flatMap { $0 == 1 ? nil : "Every \($0) hours" } ?? "Every hour"
			return .every(minutes[0] == 0 ? every : "\(every) at :\(twoDigits(minutes[0]))")
		}
		if let (first, last) = range(hour, in: 0 ... 23), minutes.count == 1 {
			return .every("Every hour from \(clock(first, minutes[0])) to \(clock(last, minutes[0]))")
		}
		guard let hours = numbers(hour, in: 0 ... 23) else {
			return nil
		}
		let times = hours.sorted().flatMap { hour in minutes.sorted().map { clock(hour, $0) } }
		return times.count <= 6 ? .at(times) : nil
	}

	// MARK: - Days

	private enum Days {
		case everyDay
		/// Days of the week, 0 = Sunday.
		case weekdays(Set<Int>)
		/// Days of every month.
		case monthly([Int])
		/// Days of one month.
		case yearly(month: Int, days: [Int])
	}

	private static func days(dayOfMonth: String, month: String, dayOfWeek: String) -> Days? {
		let anyDayOfMonth = dayOfMonth == "*" || dayOfMonth == "?"
		let anyDayOfWeek = dayOfWeek == "*" || dayOfWeek == "?"
		switch (anyDayOfMonth, month == "*", anyDayOfWeek) {
		case (true, true, true):
			return .everyDay
		case (true, true, false):
			guard let weekdays = weekdays(dayOfWeek) else {
				return nil
			}
			return weekdays.count == 7 ? .everyDay : .weekdays(weekdays)
		case (false, true, true):
			return numbers(dayOfMonth, in: 1 ... 31).map { .monthly($0.sorted()) }
		case (false, false, true):
			guard let days = numbers(dayOfMonth, in: 1 ... 31),
			      let month = numbers(month, in: 1 ... 12) ?? monthName(month).map({ [$0] }),
			      month.count == 1
			else {
				return nil
			}
			return .yearly(month: month[0], days: days.sorted())
		default:
			return nil
		}
	}

	/// A day-of-week field as a set of days, 0 = Sunday (7 too): numbers, names, lists and ranges.
	private static func weekdays(_ field: String) -> Set<Int>? {
		var days = Set<Int>()
		for item in field.split(separator: ",", omittingEmptySubsequences: false) {
			let bounds = item.split(separator: "-", omittingEmptySubsequences: false).map(String.init)
			guard (1 ... 2).contains(bounds.count) else {
				return nil
			}
			let values = bounds.compactMap(weekday)
			guard values.count == bounds.count else {
				return nil
			}
			if values.count == 1 {
				days.insert(values[0] % 7)
			}
			else {
				guard values[0] <= values[1] else {
					return nil
				}
				days.formUnion((values[0] ... values[1]).map { $0 % 7 })
			}
		}
		return days
	}

	private static func weekday(_ value: String) -> Int? {
		if let number = Int(value), (0 ... 7).contains(number) {
			return number
		}
		return weekdayAbbreviations.firstIndex(of: value)
	}

	private static func monthName(_ value: String) -> Int? {
		monthAbbreviations.firstIndex(of: value).map { $0 + 1 }
	}

	// MARK: - Sentences

	private static func sentence(_ time: Time, _ days: Days) -> String {
		switch (time, days) {
		case let (.at(times), .everyDay):
			"Every day at \(list(times))"
		case let (.at(times), .weekdays(weekdays)):
			switch weekdayPhrase(weekdays) {
			case let .named(name):
				"\(name) at \(list(times))"
			case let .listed(names):
				"Every \(names) at \(list(times))"
			}
		case let (.at(times), .monthly(days)):
			"Monthly on the \(list(days.map(ordinal))) at \(list(times))"
		case let (.at(times), .yearly(month, days)):
			"Every year on \(monthNames[month - 1]) \(list(days.map(String.init))) at \(list(times))"
		case let (.every(every), .everyDay):
			every
		case let (.every(every), .weekdays(weekdays)):
			switch weekdayPhrase(weekdays) {
			case let .named(name):
				"\(every), \(name.lowercased())"
			case let .listed(names):
				"\(every) on \(names)"
			}
		case let (.every(every), .monthly(days)):
			"\(every) on the \(list(days.map(ordinal))) of the month"
		case let (.every(every), .yearly(month, days)):
			"\(every) on \(monthNames[month - 1]) \(list(days.map(String.init)))"
		}
	}

	private enum WeekdayPhrase {
		/// "Weekdays", "Monday to Thursday" — leads a sentence on its own.
		case named(String)
		/// "Monday and Friday" — follows "Every" or "on".
		case listed(String)
	}

	/// Days of the week as words, Monday first.
	private static func weekdayPhrase(_ days: Set<Int>) -> WeekdayPhrase {
		if days == [1, 2, 3, 4, 5] {
			return .named("Weekdays")
		}
		if days == [0, 6] {
			return .named("Weekends")
		}
		// Monday first: Sunday is the week's last day here.
		let ordered = days.map { $0 == 0 ? 7 : $0 }.sorted()
		if ordered.count >= 3, ordered.last! - ordered.first! == ordered.count - 1 {
			return .named("\(weekdayNames[ordered.first! % 7]) to \(weekdayNames[ordered.last! % 7])")
		}
		return .listed(list(ordered.map { weekdayNames[$0 % 7] }))
	}

	// MARK: - Fields

	/// `*/n`.
	private static func step(_ field: String, in bounds: ClosedRange<Int>) -> Int? {
		guard field.hasPrefix("*/"), let step = Int(field.dropFirst(2)), step >= 1, step <= bounds.upperBound
		else {
			return nil
		}
		return step
	}

	/// `*/n`, `a/n` or `a-b/n`: the step, and the first and last value it gives.
	private static func steps(_ field: String, in bounds: ClosedRange<Int>) -> (Int, Int, Int)? {
		let parts = field.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
		guard parts.count == 2, let step = Int(parts[1]), step >= 1, step <= bounds.upperBound else {
			return nil
		}
		let start: Int
		let end: Int
		if parts[0] == "*" {
			(start, end) = (bounds.lowerBound, bounds.upperBound)
		}
		else if let number = Int(parts[0]), bounds.contains(number) {
			(start, end) = (number, bounds.upperBound)
		}
		else if let (first, last) = range(parts[0], in: bounds) {
			(start, end) = (first, last)
		}
		else {
			return nil
		}
		return (step, start, start + (end - start) / step * step)
	}

	/// `a-b`, with a before b.
	private static func range(_ field: String, in bounds: ClosedRange<Int>) -> (Int, Int)? {
		let parts = field.split(separator: "-", omittingEmptySubsequences: false)
		guard parts.count == 2,
		      let first = Int(parts[0]), let last = Int(parts[1]),
		      bounds.contains(first), bounds.contains(last), first < last
		else {
			return nil
		}
		return (first, last)
	}

	/// A number or a list of numbers.
	private static func numbers(_ field: String, in bounds: ClosedRange<Int>) -> [Int]? {
		var numbers: [Int] = []
		for item in field.split(separator: ",", omittingEmptySubsequences: false) {
			guard let number = Int(item), bounds.contains(number) else {
				return nil
			}
			numbers.append(number)
		}
		return numbers
	}

	// MARK: - Words

	private static func clock(_ hour: Int, _ minute: Int) -> String {
		"\(twoDigits(hour)):\(twoDigits(minute))"
	}

	private static func twoDigits(_ value: Int) -> String {
		value < 10 ? "0\(value)" : "\(value)"
	}

	/// "a", "a and b", "a, b and c".
	private static func list(_ items: [String]) -> String {
		guard items.count > 1 else {
			return items.first ?? ""
		}
		return items.dropLast().joined(separator: ", ") + " and " + items.last!
	}

	private static func ordinal(_ day: Int) -> String {
		let suffix = switch (day % 10, day % 100) {
		case (_, 11 ... 13): "th"
		case (1, _): "st"
		case (2, _): "nd"
		case (3, _): "rd"
		default: "th"
		}
		return "\(day)\(suffix)"
	}

	private static let weekdayNames = [
		"Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday",
	]
	private static let weekdayAbbreviations = ["sun", "mon", "tue", "wed", "thu", "fri", "sat"]
	private static let monthNames = [
		"January", "February", "March", "April", "May", "June",
		"July", "August", "September", "October", "November", "December",
	]
	private static let monthAbbreviations = [
		"jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec",
	]
}

/// "2h 3m ago", "1d 2h ago", "12m ago", "45s ago" or "just now" — `timeUntil` the other way.
nonisolated enum HomerScheduleFormat {
	static func timeSince(_ epochSeconds: Double, now: Date) -> String {
		let seconds = Int(now.timeIntervalSince1970.rounded(.down)) - Int(epochSeconds)
		guard seconds > 0 else {
			return "just now"
		}
		let minutes = seconds / 60
		let hours = minutes / 60
		let days = hours / 24
		if days > 0 {
			return "\(days)d \(hours % 24)h ago"
		}
		if hours > 0 {
			return "\(hours)h \(minutes % 60)m ago"
		}
		if minutes > 0 {
			return "\(minutes)m ago"
		}
		return "\(seconds)s ago"
	}
}
