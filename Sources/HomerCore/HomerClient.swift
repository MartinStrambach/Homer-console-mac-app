import ComposableArchitecture
import Foundation

/// The Homer API, addressed by the instance's base URL (see `HomerEndpoint.normalize`). Errors
/// are `HomerAPIError`s.
@DependencyClient
public struct HomerClient: Sendable {
	/// Who the current session belongs to. Throws `.unauthorized` when there is none.
	public var me: @Sendable (_ baseURL: String) async throws -> HomerUser
	public var login: @Sendable (_ baseURL: String, _ username: String, _ password: String) async throws -> HomerUser
	public var logout: @Sendable (_ baseURL: String) async throws -> Void
	public var processes: @Sendable (_ baseURL: String, _ query: HomerProcessQuery) async throws -> HomerProcessPage
	public var agentNames: @Sendable (_ baseURL: String) async throws -> [String]
	public var killProcess: @Sendable (_ baseURL: String, _ id: Int) async throws -> Void
	/// Returns the new run's id.
	public var retryProcess: @Sendable (_ baseURL: String, _ id: Int) async throws -> Int
	public var openQuestions: @Sendable (_ baseURL: String) async throws -> [HomerQuestion]
	public var answerQuestion: @Sendable (_ baseURL: String, _ id: String, _ answer: String) async throws -> Void
	/// Every question one run asked, whatever its status.
	public var runQuestions: @Sendable (_ baseURL: String, _ processId: Int) async throws -> [HomerQuestion]
	/// Cancels the dispatch of a question not answered yet, expiring the question with it.
	public var cancelDispatch: @Sendable (_ baseURL: String, _ id: Int) async throws -> Void
	/// The runners and the last orphan pod sweep.
	public var health: @Sendable (_ baseURL: String) async throws -> HomerHealth
	/// The server's Homer version.
	public var version: @Sendable (_ baseURL: String) async throws -> String?
	/// The session cookies held for the instance, for the embedded web console.
	public var sessionCookies: @Sendable (_ baseURL: String) -> [HTTPCookie] = { _ in [] }
}

extension HomerClient: DependencyKey {
	public static let liveValue = HomerClient(
		me: { try await HomerAPI.me(baseURL: $0) },
		login: { try await HomerAPI.login(baseURL: $0, username: $1, password: $2) },
		logout: { try await HomerAPI.logout(baseURL: $0) },
		processes: { try await HomerAPI.processes(baseURL: $0, query: $1) },
		agentNames: { try await HomerAPI.agentNames(baseURL: $0) },
		killProcess: { try await HomerAPI.killProcess(baseURL: $0, id: $1) },
		retryProcess: { try await HomerAPI.retryProcess(baseURL: $0, id: $1) },
		openQuestions: { try await HomerAPI.openQuestions(baseURL: $0) },
		answerQuestion: { try await HomerAPI.answerQuestion(baseURL: $0, id: $1, answer: $2) },
		runQuestions: { try await HomerAPI.questions(baseURL: $0, processId: $1) },
		cancelDispatch: { try await HomerAPI.cancelDispatch(baseURL: $0, id: $1) },
		health: { try await HomerAPI.health(baseURL: $0) },
		version: { try await HomerAPI.version(baseURL: $0) },
		sessionCookies: { HomerAPI.sessionCookies(baseURL: $0) }
	)
}

extension HomerClient: TestDependencyKey {
	public static let testValue = HomerClient()
}
