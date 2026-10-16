import Foundation
@testable import HomerCore
import Testing

@Suite("Homer proxy settings store")
struct HomerProxySettingsStoreTests {
	@Test("each instance's proxy is kept apart, across a relaunch, readable by the user alone")
	func persists() throws {
		let fileURL = FileManager.default.temporaryDirectory
			.appending(component: UUID().uuidString)
			.appending(component: "homerProxies.json")
		defer { try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent()) }

		let store = HomerProxySettingsStore(fileURL: fileURL)
		store.save(HomerProxySettings(url: "https://proxy-one.example", token: "one"), for: "http://localhost:8080")
		store.save(HomerProxySettings(url: "https://proxy-two.example", token: "two"), for: "http://localhost:8081")

		let relaunched = HomerProxySettingsStore(fileURL: fileURL)
		#expect(relaunched.settings(for: "http://localhost:8080")?.token == "one")
		#expect(relaunched.settings(for: "http://localhost:8081")?.url == "https://proxy-two.example")
		#expect(relaunched.settings(for: "http://localhost:8082") == nil)

		let permissions = try FileManager.default.attributesOfItem(atPath: fileURL.path)[.posixPermissions] as? Int
		#expect(permissions == 0o600)

		relaunched.remove(for: "http://localhost:8080")
		#expect(HomerProxySettingsStore(fileURL: fileURL).settings(for: "http://localhost:8080") == nil)
		#expect(HomerProxySettingsStore(fileURL: fileURL).settings(for: "http://localhost:8081")?.token == "two")
	}

	@Test("without a file the settings live in memory")
	func inMemory() {
		let store = HomerProxySettingsStore(fileURL: nil)
		store.save(HomerProxySettings(url: "https://proxy.example", token: "t"), for: "http://localhost:8080")
		#expect(store.settings(for: "http://localhost:8080")?.url == "https://proxy.example")
		store.remove(for: "http://localhost:8080")
		#expect(store.settings(for: "http://localhost:8080") == nil)
	}
}

@Suite("Server-sent event parser")
struct HomerServerSentEventParserTests {
	@Test("CRLF lines, several data lines and a kept id make one event; comments are skipped")
	func parses() {
		var parser = HomerServerSentEventParser()
		var events: [HomerServerSentEvent] = []
		for line in [": ping\r", "id: 12\r", "event: run.updated\r", "data: {\"a\":1,\r", "data: \"b\":2}\r", "\r", "data: plain", ""] {
			if let event = parser.consume(line: line) {
				events.append(event)
			}
		}

		#expect(events == [
			HomerServerSentEvent(name: "run.updated", id: "12", data: "{\"a\":1,\n\"b\":2}"),
			HomerServerSentEvent(name: "message", id: nil, data: "plain"),
		])
	}
}
