import Foundation

// Server-sent events (`text/event-stream`), shared by the Homer streams (`HomerAPI.events`) and
// the conversation proxy's event stream, which is read with its own request and session.

/// One event of a `text/event-stream`.
package nonisolated struct HomerServerSentEvent: Equatable, Sendable {
	package var name: String
	package var id: String?
	package var data: String

	package init(name: String, id: String?, data: String) {
		self.name = name
		self.id = id
		self.data = data
	}
}

/// The `text/event-stream` format, a line at a time: `event:`, `id:` and `data:` fields
/// accumulate until a blank line ends the event.
package nonisolated struct HomerServerSentEventParser {
	private var name: String?
	private var id: String?
	private var dataLines: [String] = []

	package init() {}

	package mutating func consume(line rawLine: String) -> HomerServerSentEvent? {
		let line = rawLine.hasSuffix("\r") ? String(rawLine.dropLast()) : rawLine
		guard !line.isEmpty else {
			defer {
				name = nil
				id = nil
				dataLines = []
			}
			guard name != nil || !dataLines.isEmpty else {
				return nil
			}
			return HomerServerSentEvent(name: name ?? "message", id: id, data: dataLines.joined(separator: "\n"))
		}
		guard !line.hasPrefix(":") else {
			return nil
		}
		let field: Substring
		var value: Substring
		if let colon = line.firstIndex(of: ":") {
			field = line[..<colon]
			value = line[line.index(after: colon)...]
			if value.hasPrefix(" ") {
				value = value.dropFirst()
			}
		}
		else {
			field = Substring(line)
			value = ""
		}
		switch field {
		case "event":
			name = String(value)
		case "id":
			id = String(value)
		case "data":
			dataLines.append(String(value))
		default:
			break
		}
		return nil
	}
}

extension HomerAPI {
	/// A server-sent event stream, parsed into its events, from a request the caller built
	/// (`Accept: text/event-stream` is set here). `onResponse` sees the response's headers
	/// before any event — the Homer streams feed their cookies back and check the status
	/// there, the proxy's stream only checks. It ends when the server closes it; cancelling the
	/// consuming task closes it from this side. Comments (heartbeat pings) are skipped.
	package static func events(
		request: URLRequest,
		session: URLSession,
		onResponse: @escaping @Sendable (HTTPURLResponse) throws -> Void
	) -> AsyncThrowingStream<HomerServerSentEvent, any Error> {
		AsyncThrowingStream { continuation in
			let task = Task {
				do {
					var request = request
					request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
					let bytes: URLSession.AsyncBytes
					let response: URLResponse
					do {
						(bytes, response) = try await session.bytes(for: request)
					}
					catch {
						throw HomerAPIError.unreachable(error.localizedDescription)
					}
					guard let http = response as? HTTPURLResponse else {
						throw HomerAPIError.unexpectedResponse
					}
					try onResponse(http)

					var parser = HomerServerSentEventParser()
					var line: [UInt8] = []
					for try await byte in bytes {
						guard byte == UInt8(ascii: "\n") else {
							line.append(byte)
							continue
						}
						if let event = parser.consume(line: String(decoding: line, as: UTF8.self)) {
							continuation.yield(event)
						}
						line.removeAll(keepingCapacity: true)
					}
					continuation.finish()
				}
				catch is CancellationError {
					continuation.finish()
				}
				catch let error as HomerAPIError {
					continuation.finish(throwing: error)
				}
				catch {
					continuation.finish(throwing: HomerAPIError.unreachable(error.localizedDescription))
				}
			}
			continuation.onTermination = { _ in task.cancel() }
		}
	}
}
