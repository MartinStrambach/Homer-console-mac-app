import Foundation
@testable import HomerCore
import Testing

@Suite("HomerAPI status check")
struct HomerAPICheckTests {
	private func response(_ status: Int) throws -> HTTPURLResponse {
		try #require(HTTPURLResponse(url: URL(string: "https://homer.example")!, statusCode: status, httpVersion: nil, headerFields: nil))
	}

	private let readOnly = Data(#"{"err":1,"msg":"Agent directory is read-only"}"#.utf8)

	/// The agent file API answers a read-only agent directory — and, since Homer 1.32.1, a
	/// permission change racing a write — with a 403 whose `msg` says so (ADR-0004).
	@Test("a 403 with a message is told in the server's words when asked")
	func forbiddenInServerWords() throws {
		#expect(throws: HomerAPIError.server(status: 403, message: "Agent directory is read-only")) {
			try HomerAPI.check(response(403), body: readOnly, refusalsInServerWords: true)
		}
	}

	@Test("a 403 is not allowed otherwise, or when it carries no message")
	func forbidden() throws {
		#expect(throws: HomerAPIError.forbidden) {
			try HomerAPI.check(response(403), body: readOnly, refusalsInServerWords: false)
		}
		#expect(throws: HomerAPIError.forbidden) {
			try HomerAPI.check(response(403), body: Data(), refusalsInServerWords: true)
		}
	}

	@Test("a 401 stays a lost session even with a message")
	func unauthorized() throws {
		#expect(throws: HomerAPIError.unauthorized) {
			try HomerAPI.check(response(401), body: Data(#"{"msg":"Unauthorized"}"#.utf8), refusalsInServerWords: true)
		}
	}
}
