import Foundation

/// Where `<command> <text>` goes — homer-slack's `route` (`src/router.ts`), so a command typed
/// here runs what the same words run as a Slack mention: `help` lists the commands, a first
/// word naming a command (in any case) runs it with the rest as the prompt, and anything else
/// runs the default command with the whole text.
public nonisolated enum HomerCommandRoute: Equatable, Sendable {
	case command(HomerCommand, prompt: String)
	case help
	/// No command is named and there is no default one.
	case unknown(command: String)

	public init(text: String, commands: [HomerCommand]) {
		let words = Self.stripMention(text).split(separator: " ").map(String.init)
		let first = words.first ?? ""
		let firstLower = first.lowercased()

		if firstLower == "help" {
			self = .help
		}
		else if let named = commands.first(where: { !$0.isDefault && $0.command.lowercased() == firstLower }) {
			self = .command(named, prompt: words.dropFirst().joined(separator: " "))
		}
		else if let fallback = commands.first(where: \.isDefault) {
			self = .command(fallback, prompt: words.joined(separator: " "))
		}
		else {
			self = .unknown(command: first)
		}
	}

	/// The text with Slack user mentions (`<@U123>`) removed and its whitespace collapsed.
	static func stripMention(_ text: String) -> String {
		text.replacing(/<@[^>]+>/, with: " ")
			.split(whereSeparator: \.isWhitespace)
			.joined(separator: " ")
	}
}
