import ComposableArchitecture
import Foundation
import HomerCore

/// The Continuations page's part of the Homer API: continuations and ask-and-dispatches. Errors
/// are `HomerAPIError`s.
@DependencyClient
public struct HomerContinuationsClient: Sendable {
	/// One page of the continuations the user may see, newest first.
	public var continuations: @Sendable (
		_ baseURL: String,
		_ query: HomerRecordQuery<HomerContinuationStatus>
	) async throws -> HomerRecordPage<HomerContinuation>
	/// One continuation, read again for its detail.
	public var continuation: @Sendable (_ baseURL: String, _ id: Int) async throws -> HomerContinuation
	/// Cancels a pending continuation: its agent never starts.
	public var cancel: @Sendable (_ baseURL: String, _ id: Int) async throws -> Void
	/// How many pending continuations the user may see, for the page's badge.
	public var pendingCount: @Sendable (_ baseURL: String) async throws -> Int
	/// One page of the ask-and-dispatches the user may see, newest first.
	public var dispatches: @Sendable (
		_ baseURL: String,
		_ query: HomerRecordQuery<HomerDispatchStatus>
	) async throws -> HomerRecordPage<HomerDispatch>
	/// One dispatch, read again for its detail.
	public var dispatch: @Sendable (_ baseURL: String, _ id: Int) async throws -> HomerDispatch
	/// Cancels a pending dispatch: its question expires and its agent never starts.
	public var cancelDispatch: @Sendable (_ baseURL: String, _ id: Int) async throws -> Void
}

extension HomerContinuationsClient: DependencyKey {
	public static let liveValue = HomerContinuationsClient(
		continuations: { try await HomerAPI.continuations(baseURL: $0, query: $1) },
		continuation: { try await HomerAPI.continuation(baseURL: $0, id: $1) },
		cancel: { try await HomerAPI.cancelContinuation(baseURL: $0, id: $1) },
		pendingCount: { try await HomerAPI.pendingContinuationCount(baseURL: $0) },
		dispatches: { try await HomerAPI.dispatches(baseURL: $0, query: $1) },
		dispatch: { try await HomerAPI.dispatch(baseURL: $0, id: $1) },
		cancelDispatch: { try await HomerAPI.cancelPendingDispatch(baseURL: $0, id: $1) }
	)
}

extension HomerContinuationsClient: TestDependencyKey {
	public static let testValue = HomerContinuationsClient()
}
