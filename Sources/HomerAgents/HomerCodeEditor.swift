import AppKit
import HomerUI
import SwiftUI

/// The open file's text (the console's Monaco editor, `agent-file-editor.tsx`): monospaced at
/// 13 pt, unwrapped, with line numbers, colored by the file's language, a tab indenting by two
/// spaces and a new line keeping the last one's indent. Undo, and ⌘F's find bar, are the text
/// view's own.
///
/// An `NSTextView` on TextKit 1: the line number gutter walks its layout manager, and the colors
/// are the layout manager's temporary attributes, which neither touch the text nor its undo.
/// The schema hints Monaco gives a definition are left to the server, which checks it on save.
///
/// The gutter is a view beside the scroll view, not its `NSRulerView`: a ruler sits in the clip
/// view's left content inset, which the text view's own scrolling to the caret ignores — the
/// text opened, or jumped back to, a ruler's width short of its left edge.
struct HomerCodeEditor: NSViewRepresentable {
	@Binding
	var text: String
	let language: HomerAgentFileLanguage
	let isEditable: Bool
	/// The file shown: a new one starts with an empty undo stack, scrolled to the top.
	let documentID: String?

	@Environment(\.uiFontScale)
	private var scale

	/// Larger files are not colored: the whole text is matched again on every change.
	static let maxHighlightedLength = 200_000

	func makeNSView(context: Context) -> HomerCodeEditorContainer {
		let textView = NSTextView(usingTextLayoutManager: false)
		textView.delegate = context.coordinator
		textView.isRichText = false
		textView.importsGraphics = false
		textView.allowsUndo = true
		textView.usesFindBar = true
		textView.isIncrementalSearchingEnabled = true
		textView.isAutomaticQuoteSubstitutionEnabled = false
		textView.isAutomaticDashSubstitutionEnabled = false
		textView.isAutomaticTextReplacementEnabled = false
		textView.isAutomaticSpellingCorrectionEnabled = false
		textView.isAutomaticTextCompletionEnabled = false
		textView.isAutomaticDataDetectionEnabled = false
		textView.isAutomaticLinkDetectionEnabled = false
		textView.isContinuousSpellCheckingEnabled = false
		textView.isGrammarCheckingEnabled = false
		textView.smartInsertDeleteEnabled = false
		textView.textContainerInset = NSSize(width: 4, height: 6)
		textView.drawsBackground = true
		textView.backgroundColor = .textBackgroundColor
		textView.textColor = .textColor

		// Unwrapped, as Monaco is: the container is as wide as the longest line.
		textView.isHorizontallyResizable = true
		textView.isVerticallyResizable = true
		textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
		textView.autoresizingMask = [.width, .height]
		textView.textContainer?.widthTracksTextView = false
		textView.textContainer?.containerSize = NSSize(
			width: CGFloat.greatestFiniteMagnitude,
			height: CGFloat.greatestFiniteMagnitude
		)

		let scrollView = NSScrollView()
		scrollView.hasVerticalScroller = true
		scrollView.hasHorizontalScroller = true
		scrollView.autohidesScrollers = true
		scrollView.borderType = .noBorder
		scrollView.documentView = textView

		let gutter = HomerLineNumberGutter(textView: textView)
		context.coordinator.gutter = gutter

		scrollView.contentView.postsBoundsChangedNotifications = true
		NotificationCenter.default.addObserver(
			context.coordinator,
			selector: #selector(Coordinator.boundsDidChange),
			name: NSView.boundsDidChangeNotification,
			object: scrollView.contentView
		)
		return HomerCodeEditorContainer(scrollView: scrollView, gutter: gutter)
	}

	func updateNSView(_ container: HomerCodeEditorContainer, context: Context) {
		let scrollView = container.scrollView
		guard let textView = scrollView.documentView as? NSTextView else {
			return
		}
		let coordinator = context.coordinator
		coordinator.parent = self
		textView.isEditable = isEditable

		let font = NSFont.monospacedSystemFont(ofSize: UIFontScale.pointSize(of: .body) * scale, weight: .regular)
		var needsHighlight = false
		if coordinator.font != font {
			coordinator.font = font
			textView.font = font
			textView.typingAttributes = [.font: font, .foregroundColor: NSColor.textColor]
			coordinator.gutter?.font = NSFont.monospacedDigitSystemFont(ofSize: font.pointSize * 0.85, weight: .regular)
			needsHighlight = true
		}

		if coordinator.documentID != documentID {
			coordinator.documentID = documentID
			textView.string = text
			textView.undoManager?.removeAllActions()
			textView.setSelectedRange(NSRange(location: 0, length: 0))
			coordinator.scrollsToStart = true
			needsHighlight = true
		}
		else if textView.string != text {
			// Read again from the server: the selection stays where it can.
			let selection = textView.selectedRange()
			textView.string = text
			let length = (text as NSString).length
			textView.setSelectedRange(NSRange(location: min(selection.location, length), length: 0))
			needsHighlight = true
		}

		if coordinator.language != language {
			coordinator.language = language
			needsHighlight = true
		}
		if needsHighlight {
			coordinator.highlight(textView)
		}
		if coordinator.scrollsToStart {
			coordinator.scrollsToStart = false
			Self.scrollToStart(scrollView)
			// Again once laid out: a new view has no size yet.
			DispatchQueue.main.async {
				Self.scrollToStart(scrollView)
			}
		}
	}

	/// The top left of the text. Not `scrollRangeToVisible` at 0, which only brings the caret
	/// into a clip view that may not have its size yet.
	private static func scrollToStart(_ scrollView: NSScrollView) {
		let clipView = scrollView.contentView
		let insets = clipView.contentInsets
		clipView.scroll(to: NSPoint(x: -insets.left, y: -insets.top))
		scrollView.reflectScrolledClipView(clipView)
	}

	static func dismantleNSView(_ container: HomerCodeEditorContainer, coordinator: Coordinator) {
		NotificationCenter.default.removeObserver(coordinator)
	}

	func makeCoordinator() -> Coordinator {
		Coordinator(parent: self)
	}

	@MainActor
	final class Coordinator: NSObject, NSTextViewDelegate {
		var parent: HomerCodeEditor
		var font: NSFont?
		var documentID: String??
		var language: HomerAgentFileLanguage?
		/// A new file was set: show its start once the update is done.
		var scrollsToStart = false
		weak var gutter: HomerLineNumberGutter?

		init(parent: HomerCodeEditor) {
			self.parent = parent
		}

		func textDidChange(_ notification: Notification) {
			guard let textView = notification.object as? NSTextView else {
				return
			}
			parent.text = textView.string
			highlight(textView)
		}

		func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
			switch commandSelector {
			case #selector(NSResponder.insertTab(_:)):
				textView.insertText("  ", replacementRange: textView.selectedRange())
				return true
			case #selector(NSResponder.insertNewline(_:)):
				let string = textView.string as NSString
				let location = textView.selectedRange().location
				let line = string.substring(with: string.lineRange(for: NSRange(location: location, length: 0)))
				let indent = line.prefix { $0 == " " || $0 == "\t" }
				textView.insertText("\n" + indent, replacementRange: textView.selectedRange())
				return true
			default:
				return false
			}
		}

		@objc
		func boundsDidChange(_ notification: Notification) {
			gutter?.needsDisplay = true
		}

		func highlight(_ textView: NSTextView) {
			gutter?.updateThickness()
			gutter?.needsDisplay = true
			guard let layoutManager = textView.layoutManager else {
				return
			}
			let string = textView.string
			let whole = NSRange(location: 0, length: (string as NSString).length)
			layoutManager.removeTemporaryAttribute(.foregroundColor, forCharacterRange: whole)
			guard whole.length <= HomerCodeEditor.maxHighlightedLength, let language else {
				return
			}
			for token in HomerSyntaxHighlighter.tokens(in: string, language: language) {
				layoutManager.addTemporaryAttribute(.foregroundColor, value: token.kind.color, forCharacterRange: token.range)
			}
		}
	}
}

/// The gutter and the scroll view side by side, the gutter as wide as its numbers need.
final class HomerCodeEditorContainer: NSView {
	let scrollView: NSScrollView
	let gutter: HomerLineNumberGutter

	init(scrollView: NSScrollView, gutter: HomerLineNumberGutter) {
		self.scrollView = scrollView
		self.gutter = gutter
		super.init(frame: .zero)
		addSubview(gutter)
		addSubview(scrollView)
	}

	@available(*, unavailable)
	required init?(coder: NSCoder) {
		fatalError("init(coder:) is not supported")
	}

	override var isFlipped: Bool {
		true
	}

	override func layout() {
		super.layout()
		let width = min(gutter.thickness, bounds.width)
		gutter.frame = NSRect(x: 0, y: 0, width: width, height: bounds.height)
		scrollView.frame = NSRect(x: width, y: 0, width: bounds.width - width, height: bounds.height)
	}
}

/// Line numbers beside the editor, one per line of the text (not per wrapped fragment — the
/// editor does not wrap), the current line's in the text color, following the text's scrolling.
final class HomerLineNumberGutter: NSView {
	var font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular) {
		didSet {
			updateThickness()
			needsDisplay = true
		}
	}

	private weak var textView: NSTextView?

	init(textView: NSTextView) {
		self.textView = textView
		super.init(frame: .zero)
	}

	/// Its width, set by `updateThickness`; the container lays it out.
	private(set) var thickness: CGFloat = 36 {
		didSet {
			superview?.needsLayout = true
		}
	}

	@available(*, unavailable)
	required init?(coder: NSCoder) {
		fatalError("init(coder:) is not supported")
	}

	/// Wide enough for the last line's number, two digits at least.
	func updateThickness() {
		guard let textView else {
			return
		}
		let string = textView.string as NSString
		let lineCount = Self.lineNumber(of: string.length, in: string)
		let digitWidth = ("8" as NSString).size(withAttributes: [.font: font]).width
		let width = (CGFloat(max(String(lineCount).count, 2)) * digitWidth + 16).rounded(.up)
		if abs(thickness - width) > 0.5 {
			thickness = width
		}
	}

	override var isFlipped: Bool {
		true
	}

	override func draw(_ dirtyRect: NSRect) {
		NSColor.textBackgroundColor.setFill()
		bounds.fill()
		drawNumbers()
	}

	private func drawNumbers() {
		guard let textView, let layoutManager = textView.layoutManager, let container = textView.textContainer else {
			return
		}
		let string = textView.string as NSString
		let selected = string.lineRange(for: NSRange(location: min(textView.selectedRange().location, string.length), length: 0))
		let glyphs = layoutManager.glyphRange(forBoundingRect: textView.visibleRect, in: container)
		let visible = layoutManager.characterRange(forGlyphRange: glyphs, actualGlyphRange: nil)
		var lineNumber = Self.lineNumber(of: visible.location, in: string)
		var index = string.lineRange(for: NSRange(location: visible.location, length: 0)).location
		let inset = textView.textContainerInset.height

		while index < string.length, index <= NSMaxRange(visible) {
			let line = string.lineRange(for: NSRange(location: index, length: 0))
			let glyph = layoutManager.glyphIndexForCharacter(at: line.location)
			let fragment = layoutManager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
			draw(lineNumber, in: fragment, inset: inset, isCurrent: line.location == selected.location)
			lineNumber += 1
			index = NSMaxRange(line)
		}
		// The empty last line after a trailing newline, or of an empty file.
		if index == string.length, string.length == 0 || string.hasSuffix("\n") {
			let fragment = layoutManager.extraLineFragmentRect
			if fragment.height > 0 {
				draw(lineNumber, in: fragment, inset: inset, isCurrent: selected.location == string.length)
			}
		}
	}

	private func draw(_ number: Int, in fragment: NSRect, inset: CGFloat, isCurrent: Bool) {
		guard let textView else {
			return
		}
		let top = convert(NSPoint(x: 0, y: fragment.minY + inset), from: textView).y
		let label = String(number) as NSString
		let attributes: [NSAttributedString.Key: Any] = [
			.font: font,
			.foregroundColor: isCurrent ? NSColor.textColor : NSColor.tertiaryLabelColor,
		]
		let size = label.size(withAttributes: attributes)
		label.draw(
			at: NSPoint(x: bounds.width - size.width - 8, y: top + (fragment.height - size.height) / 2),
			withAttributes: attributes
		)
	}

	/// 1-based: the newlines before `location`, plus one.
	static func lineNumber(of location: Int, in string: NSString) -> Int {
		var count = 1
		var searchRange = NSRange(location: 0, length: min(location, string.length))
		while true {
			let found = string.range(of: "\n", options: .literal, range: searchRange)
			guard found.location != NSNotFound else {
				return count
			}
			count += 1
			searchRange = NSRange(location: NSMaxRange(found), length: NSMaxRange(searchRange) - NSMaxRange(found))
		}
	}
}

/// The colors of the editor's text: keys, strings, numbers and literals, comments, and
/// Markdown headings — a few patterns per language, far short of Monaco's grammars, which is
/// all an agent's YAML, JSON and scripts need to read well.
nonisolated enum HomerSyntaxHighlighter {
	enum Kind: Equatable, Sendable {
		case key
		case string
		case literal
		case comment
		case heading

		var color: NSColor {
			switch self {
			case .key: .systemBlue
			case .string: .systemRed
			case .literal: .systemOrange
			case .comment: .secondaryLabelColor
			case .heading: .systemPurple
			}
		}
	}

	struct Token: Equatable, Sendable {
		var range: NSRange
		var kind: Kind
	}

	/// A pattern, the capture group it colors (0 for the whole match), and its color. A
	/// language's rules apply in order, a later one coloring over an earlier one.
	private struct Rule {
		let regex: NSRegularExpression
		let group: Int
		let kind: Kind

		init(_ pattern: String, group: Int = 0, _ kind: Kind) {
			// The patterns are constants: one that does not compile is a bug found by the tests.
			regex = try! NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines])
			self.group = group
			self.kind = kind
		}
	}

	private static let doubleQuoted = #""(?:[^"\\\n]|\\.)*""#
	private static let hashComment = Rule(#"(?:^|[ \t])(#.*)$"#, group: 1, .comment)

	private static let yaml: [Rule] = [
		Rule(#"^[ \t]*(?:-[ \t]+)?("[^"\n]*"|'[^'\n]*'|[^\s#'"\-][^:#\n]*?)[ \t]*:(?=[ \t]|$)"#, group: 1, .key),
		Rule(#"(?:^|[ \t\[{,])("# + doubleQuoted + #"|'(?:[^'\n]|'')*')"#, group: 1, .string),
		Rule(#"(?<=:[ \t]|-[ \t])(?:true|false|null|~|-?\d+(?:\.\d+)?)(?=[ \t]*(?:#.*)?$)"#, .literal),
		hashComment,
	]

	private static let json: [Rule] = [
		Rule(#"(?<![\w"])(?:-?\d+(?:\.\d+)?(?:[eE][+-]?\d+)?|true|false|null)(?![\w"])"#, .literal),
		Rule(doubleQuoted, .string),
		Rule("(" + doubleQuoted + #")[ \t]*:"#, group: 1, .key),
	]

	private static let script: [Rule] = [
		Rule(doubleQuoted + #"|'[^'\n]*'"#, .string),
		hashComment,
	]

	private static let javascript: [Rule] = [
		Rule(doubleQuoted + #"|'(?:[^'\\\n]|\\.)*'|`(?:[^`\\\n]|\\.)*`"#, .string),
		Rule(#"(?:^|[ \t])(//.*)$"#, group: 1, .comment),
	]

	private static let markdown: [Rule] = [
		Rule(#"`[^`\n]+`"#, .string),
		Rule(#"^#{1,6}[ \t].*$"#, .heading),
	]

	static func tokens(in string: String, language: HomerAgentFileLanguage) -> [Token] {
		let rules: [Rule] = switch language {
		case .yaml: yaml
		case .json: json
		case .shell, .python: script
		case .javascript, .typescript: javascript
		case .markdown: markdown
		case .plaintext: []
		}
		let whole = NSRange(location: 0, length: (string as NSString).length)
		return rules.flatMap { rule in
			rule.regex.matches(in: string, range: whole).compactMap { match in
				let range = match.range(at: rule.group)
				return range.location == NSNotFound || range.length == 0 ? nil : Token(range: range, kind: rule.kind)
			}
		}
	}
}
