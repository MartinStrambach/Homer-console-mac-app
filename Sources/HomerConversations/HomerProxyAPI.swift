import Foundation
import HomerCore
import Synchronization

/// The conversation proxy's API. Unlike the Homer calls it is another host with a Bearer token of
/// its own, so it has its own sessions rather than going through `HomerAPI.send` and the
/// instance's cookie jar; what it shares with them is the status check and the event-stream
/// reader. Errors are `HomerAPIError`s: a 401 is a token the proxy does not know, told in the
/// proxy's own words otherwise.
package nonisolated enum HomerProxyAPI {
	private static let timeout: TimeInterval = 30
	/// The event stream idles between events, pinged every 15 s; the timeout is an idle one.
	private static let streamTimeout: TimeInterval = 300

	private static let sessions = Mutex<[String: URLSession]>([:])

	/// One session per proxy, with no cookies, for the reason `HomerAPI` keeps one per instance.
	private static func session(for url: String) -> URLSession {
		sessions.withLock { sessions in
			if let session = sessions[url] {
				return session
			}
			let configuration = URLSessionConfiguration.default
			configuration.httpCookieStorage = nil
			configuration.httpCookieAcceptPolicy = .never
			configuration.httpShouldSetCookies = false
			let session = URLSession(configuration: configuration)
			sessions[url] = session
			return session
		}
	}

	package static func me(proxy: HomerProxySettings) async throws -> HomerProxyUser {
		try await HomerAPI.decode(HomerProxyUser.self, from: send("GET", "/me", proxy: proxy))
	}

	package static func workflows(proxy: HomerProxySettings) async throws -> [HomerWorkflow] {
		try await HomerAPI.decode([HomerWorkflow].self, from: send("GET", "/workflows", proxy: proxy))
	}

	package static func conversations(proxy: HomerProxySettings, limit: Int, cursor: String?) async throws -> HomerConversationPage {
		var queryItems = [URLQueryItem(name: "limit", value: String(limit))]
		if let cursor {
			queryItems.append(URLQueryItem(name: "cursor", value: cursor))
		}
		let data = try await send("GET", "/conversations", proxy: proxy, queryItems: queryItems)
		return try HomerAPI.decode(HomerConversationPage.self, from: data)
	}

	package static func conversation(proxy: HomerProxySettings, id: String) async throws -> HomerConversationThread {
		let data = try await send("GET", "/conversations/" + escaped(id), proxy: proxy)
		return try HomerAPI.decode(HomerConversationThread.self, from: data)
	}

	/// Starts a conversation: the proxy runs `command`'s workflow (`""` the default) with `text`
	/// as the prompt, the way the connector runs a mention.
	package static func createConversation(proxy: HomerProxySettings, command: String, text: String) async throws -> HomerConversationCreated {
		let body = try JSONEncoder().encode(NewConversation(command: command, text: text))
		let data = try await send("POST", "/conversations", proxy: proxy, body: body)
		return try HomerAPI.decode(HomerConversationCreated.self, from: data)
	}

	/// Continues a conversation: the same workflow, the same thread key, so the agent carries on
	/// its session.
	package static func sendMessage(proxy: HomerProxySettings, id: String, text: String) async throws -> HomerConversationReply {
		let body = try JSONEncoder().encode(NewMessage(text: text))
		let data = try await send("POST", "/conversations/" + escaped(id) + "/messages", proxy: proxy, body: body)
		return try HomerAPI.decode(HomerConversationReply.self, from: data)
	}

	/// The proxy's event stream, resumed from `lastEventID` when one is known. A `.connected`
	/// event comes first, when the proxy has accepted the request; the stream then yields what
	/// the proxy sends, skipping events this version does not know.
	package static func events(proxy: HomerProxySettings, lastEventID: String?) -> AsyncThrowingStream<HomerConversationEvent, any Error> {
		let request: URLRequest
		do {
			var headers: [(name: String, value: String)] = []
			if let lastEventID {
				headers.append((name: "Last-Event-ID", value: lastEventID))
			}
			request = try makeRequest("GET", "/events", proxy: proxy, headers: headers, timeout: streamTimeout)
		}
		catch {
			return AsyncThrowingStream { $0.finish(throwing: error) }
		}
		return AsyncThrowingStream { continuation in
			let task = Task {
				let events = HomerAPI.events(request: request, session: session(for: proxy.url)) { http in
					try HomerAPI.check(http, body: Data(), refusalsInServerWords: true)
					continuation.yield(HomerConversationEvent(kind: .connected))
				}
				do {
					for try await event in events {
						if let event = HomerConversationEvent(event) {
							continuation.yield(event)
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

	// MARK: - Requests

	private struct NewConversation: Encodable {
		var command: String
		var text: String
	}

	private struct NewMessage: Encodable {
		var text: String
	}

	private static func escaped(_ id: String) -> String {
		id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed.subtracting(CharacterSet(charactersIn: "/"))) ?? id
	}

	private static func send(
		_ method: String,
		_ path: String,
		proxy: HomerProxySettings,
		queryItems: [URLQueryItem] = [],
		body: Data? = nil
	) async throws -> Data {
		let request = try makeRequest(method, path, proxy: proxy, queryItems: queryItems, body: body, timeout: timeout)
		let data: Data
		let response: URLResponse
		do {
			(data, response) = try await session(for: proxy.url).data(for: request)
		}
		catch {
			throw HomerAPIError.unreachable(error.localizedDescription)
		}
		guard let http = response as? HTTPURLResponse else {
			throw HomerAPIError.unexpectedResponse
		}
		// Every refusal in the proxy's words: a 404 is an unknown conversation, a 502 Homer
		// refusing the run, both with a `msg`.
		try HomerAPI.check(http, body: data, refusalsInServerWords: true)
		return data
	}

	private static func makeRequest(
		_ method: String,
		_ path: String,
		proxy: HomerProxySettings,
		queryItems: [URLQueryItem] = [],
		headers: [(name: String, value: String)] = [],
		body: Data? = nil,
		timeout: TimeInterval
	) throws -> URLRequest {
		var base = proxy.url
		while base.hasSuffix("/") {
			base.removeLast()
		}
		guard var components = URLComponents(string: base + path) else {
			throw HomerAPIError.unexpectedResponse
		}
		if !queryItems.isEmpty {
			components.queryItems = queryItems
		}
		guard let url = components.url else {
			throw HomerAPIError.unexpectedResponse
		}
		var request = URLRequest(url: url, timeoutInterval: timeout)
		request.httpMethod = method
		request.httpBody = body
		for header in headers {
			request.setValue(header.value, forHTTPHeaderField: header.name)
		}
		request.setValue("Bearer " + proxy.token, forHTTPHeaderField: "Authorization")
		request.setValue("application/json", forHTTPHeaderField: "Accept")
		if body != nil {
			request.setValue("application/json", forHTTPHeaderField: "Content-Type")
		}
		return request
	}
}
