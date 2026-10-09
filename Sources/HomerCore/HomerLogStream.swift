import Foundation

// The live tail of a command's output (`useProcessLogStream` in the console's
// `lib/api/streams.ts`), read by a run's page and by the agent editor's debug runs.

/// What the live tail of a command's output (`GET /api/v1/stream/processes/{id}/logs`) sends.
public nonisolated enum HomerLogEvent: Equatable, Sendable {
	/// New bytes, and the file's length after them (the SSE event's id).
	case chunk(text: String, endOffset: Int)
	/// The process ended and the last bytes were sent.
	case end
}

/// A command's output on the server: `stdout` is `cmd_N.out`, `stderr` `cmd_N.err`.
public nonisolated enum HomerOutputStream: String, CaseIterable, Equatable, Sendable {
	case stdout
	case stderr

	/// The log stream's `stream` parameter.
	package var apiValue: String {
		self == .stdout ? "out" : "err"
	}

	public var title: String {
		self == .stdout ? "Stdout" : "Stderr"
	}
}

extension HomerAPI {
	/// Tails command `executionIndex`'s output from byte `offset` on: the server sends what the
	/// file holds past it, then new bytes as they are written, and ends once the run has. A
	/// command that has not written its first byte yet answers 404.
	package static func logEvents(
		baseURL: String,
		processId: Int,
		executionIndex: Int,
		stream: HomerOutputStream,
		offset: Int
	) -> AsyncThrowingStream<HomerLogEvent, any Error> {
		let events = HomerAPI.events(
			"/api/v1/stream/processes/\(processId)/logs",
			baseURL: baseURL,
			queryItems: [
				URLQueryItem(name: "cmd", value: String(executionIndex)),
				URLQueryItem(name: "stream", value: stream.apiValue),
			],
			// The byte offset to resume from (absent: from the start of the file).
			headers: [("Last-Event-ID", String(offset))]
		)
		return AsyncThrowingStream { continuation in
			let task = Task {
				do {
					for try await event in events {
						switch event.name {
						case "log.chunk":
							struct Chunk: Decodable {
								var content: String
							}
							guard let endOffset = event.id.flatMap(Int.init),
							      let chunk = try? JSONDecoder().decode(Chunk.self, from: Data(event.data.utf8))
							else {
								continue
							}
							continuation.yield(.chunk(text: chunk.content, endOffset: endOffset))
						case "log.end":
							continuation.yield(.end)
						default:
							continue
						}
					}
					continuation.finish()
				}
				catch {
					continuation.finish(throwing: error)
				}
			}
			continuation.onTermination = { _ in task.cancel() }
		}
	}
}
