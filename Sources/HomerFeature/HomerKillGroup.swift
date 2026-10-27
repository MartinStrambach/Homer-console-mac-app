import HomerCore

/// Which runs the process list's "Kill All" kills: the killable statuses (`isKillable`), one or
/// both.
public enum HomerKillGroup: CaseIterable, Equatable, Sendable {
	case working
	case created
	case workingAndCreated

	public var statuses: Set<HomerProcessStatus> {
		switch self {
		case .working:
			[.working]
		case .created:
			[.created]
		case .workingAndCreated:
			[.working, .created]
		}
	}

	/// The menu item's title.
	public var title: String {
		switch self {
		case .working:
			"Working Runs…"
		case .created:
			"Created Runs…"
		case .workingAndCreated:
			"Working and Created Runs…"
		}
	}

	/// "3 working runs", "1 created run", "no working or created runs".
	func runs(_ count: Int) -> String {
		let adjective = switch self {
		case .working:
			"working"
		case .created:
			"created"
		case .workingAndCreated:
			count == 0 ? "working or created" : "working and created"
		}
		return "\(count == 0 ? "no" : String(count)) \(adjective) \(count == 1 ? "run" : "runs")"
	}
}
