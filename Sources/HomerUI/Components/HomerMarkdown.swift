import Foundation

/// Markdown written by an agent — a question, a chat message — as the console renders it.
package enum HomerMarkdown {
	/// Inline formatting only, with the line breaks kept. Block syntax (lists, headings) shows as
	/// written, which still reads. Images never load: `Text` does not fetch them, which is the
	/// point — an agent-supplied image URL would otherwise beacon on view, the reason the console
	/// renders only their alt text.
	package static func inline(_ text: String) -> AttributedString {
		let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
		return (try? AttributedString(markdown: text, options: options)) ?? AttributedString(text)
	}
}
