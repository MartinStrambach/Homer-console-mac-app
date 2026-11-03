import Foundation
import HomerCore

/// The Continuations page's calls: continuations (`getContinuations`/`cancelContinuation` in the
/// console's `lib/api/client.ts`) and ask-and-dispatches (`/api/v1/dispatches`, which the
/// console only cancels). The server lists only the records the user may see, newest first.
extension HomerAPI {
	static func continuations(
		baseURL: String,
		query: HomerRecordQuery<HomerContinuationStatus>
	) async throws -> HomerRecordPage<HomerContinuation> {
		let data = try await send("GET", "/api/v1/continuations", baseURL: baseURL, queryItems: query.queryItems)
		let list = try decode(HomerContinuationList.self, from: data)
		return HomerRecordPage(items: list.continuations, total: list.total)
	}

	static func continuation(baseURL: String, id: Int) async throws -> HomerContinuation {
		try await decode(HomerContinuation.self, from: send("GET", "/api/v1/continuations/\(id)", baseURL: baseURL))
	}

	/// How many pending continuations the user may see — the console's sidebar badge
	/// (`usePendingContinuationsCount`). `total` counts past the page, so one row is enough.
	static func pendingContinuationCount(baseURL: String) async throws -> Int {
		try await continuations(baseURL: baseURL, query: HomerRecordQuery(status: .pending, limit: 1)).total
	}

	/// Answers 409 when the continuation is no longer pending, 404 when it is gone or not the
	/// user's to control.
	static func cancelContinuation(baseURL: String, id: Int) async throws {
		_ = try await send("DELETE", "/api/v1/continuations/\(id)", baseURL: baseURL)
	}

	static func dispatches(
		baseURL: String,
		query: HomerRecordQuery<HomerDispatchStatus>
	) async throws -> HomerRecordPage<HomerDispatch> {
		let data = try await send("GET", "/api/v1/dispatches", baseURL: baseURL, queryItems: query.queryItems)
		let list = try decode(HomerDispatchList.self, from: data)
		return HomerRecordPage(items: list.dispatches, total: list.total)
	}

	static func dispatch(baseURL: String, id: Int) async throws -> HomerDispatch {
		try await decode(HomerDispatch.self, from: send("GET", "/api/v1/dispatches/\(id)", baseURL: baseURL))
	}

	/// Expires the dispatch's question, so its agent never starts. Answers 409 once the question
	/// was answered or cancelled, 404 when it is gone or not the user's to control.
	static func cancelPendingDispatch(baseURL: String, id: Int) async throws {
		_ = try await send("DELETE", "/api/v1/dispatches/\(id)", baseURL: baseURL)
	}
}
