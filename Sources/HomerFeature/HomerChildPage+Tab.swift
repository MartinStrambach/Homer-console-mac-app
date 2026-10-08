import HomerCore

extension HomerChildPage {
	/// The page reducer behind a tab of the console, if it has one.
	init?(_ tab: HomerConsoleReducer.Tab) {
		switch tab {
		case .processes, .questions:
			return nil
		case .continuations:
			self = .continuations
		case .agents:
			self = .agents
		case .schedules:
			self = .schedules
		case .costs:
			self = .costs
		}
	}
}
