import Foundation
import HomerCore
import HomerUI
import SwiftUI

extension HomerProcess {
	/// Whether the run says anything about the files its workspace purge keeps: the globs it
	/// declared, or that the server's cap cut them short.
	var hasRetention: Bool {
		retainArtifacts?.isEmpty == false || retainedTruncated == true
	}
}

/// A `workspace.retain.artifacts` glob, matched as Homer matches it: Java's `glob:` path
/// matcher (`ArtifactRetention.matchedFiles`) against the path relative to the artifacts
/// directory. `*` and `?` stay within one path segment, `**` crosses them, `{a,b}` is either
/// and `[...]` (`[!...]` negated) a character class.
nonisolated struct HomerArtifactGlob {
	private let regex: Regex<AnyRegexOutput>

	init?(_ glob: String) {
		guard let pattern = Self.regexPattern(glob), let regex = try? Regex(pattern) else {
			return nil
		}
		self.regex = regex
	}

	func matches(_ path: String) -> Bool {
		path.wholeMatch(of: regex) != nil
	}

	/// The glob as a regular expression, as `sun.nio.fs.Globs.toRegexPattern` builds it; nil for
	/// a glob Java would reject (an unclosed group or class, a nested group).
	static func regexPattern(_ glob: String) -> String? {
		let characters = Array(glob)
		var pattern = ""
		var index = 0
		var inGroup = false
		while index < characters.count {
			let character = characters[index]
			index += 1
			switch character {
			case "\\":
				guard index < characters.count else {
					return nil
				}
				pattern += NSRegularExpression.escapedPattern(for: String(characters[index]))
				index += 1
			case "*":
				if index < characters.count, characters[index] == "*" {
					pattern += ".*"
					index += 1
				}
				else {
					pattern += "[^/]*"
				}
			case "?":
				pattern += "[^/]"
			case "{":
				guard !inGroup else {
					return nil
				}
				inGroup = true
				pattern += "(?:(?:"
			case "}" where inGroup:
				inGroup = false
				pattern += "))"
			case "," where inGroup:
				pattern += ")|(?:"
			case "[":
				guard let end = characters[index...].firstIndex(of: "]") else {
					return nil
				}
				var members = characters[index..<end]
				var negated = false
				if members.first == "!" {
					negated = true
					members = members.dropFirst()
				}
				let escaped = members.map { $0 == "\\" || $0 == "[" || $0 == "^" ? "\\\($0)" : String($0) }.joined()
				// A class never matches the separator, as in Java.
				pattern += negated ? "[^/\(escaped)]" : "(?:(?!/)[\(escaped)])"
				index = end + 1
			default:
				pattern += NSRegularExpression.escapedPattern(for: String(character))
			}
		}
		return inGroup ? nil : pattern
	}
}

/// What survives the run's workspace purge (ADR-0053): the artifact globs it declared, and
/// whether the server's byte cap left some of their files out.
struct HomerRetainedArtifactsSection: View {
	let process: HomerProcess

	var body: some View {
		HomerDetailSection(
			"Kept After Purge",
			subtitle: "Artifacts that survive the workspace purge",
			systemImage: "archivebox"
		) {
			VStack(alignment: .leading, spacing: 8) {
				if let globs = process.retainArtifacts, !globs.isEmpty {
					HomerFlowLayout(spacing: 6) {
						ForEach(globs, id: \.self) { glob in
							HomerChip(glob, monospaced: true)
						}
					}
					Text("Matching files stay downloadable from Artifacts until the run's record is deleted.")
						.scaledFont(.caption)
						.foregroundStyle(.secondary)
						.fixedSize(horizontal: false, vertical: true)
				}
				if process.retainedTruncated == true {
					Label {
						Text("Some matching files were not kept: together they passed the server's retained-artifact cap (maxRetainedArtifactBytes).")
							.fixedSize(horizontal: false, vertical: true)
					} icon: {
						Image(systemName: "exclamationmark.triangle.fill")
					}
					.scaledFont(.callout)
					.foregroundStyle(.orange)
				}
			}
			.frame(maxWidth: .infinity, alignment: .leading)
		}
	}
}
