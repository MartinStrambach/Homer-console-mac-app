import ComposableArchitecture
import Foundation
import HomerCore

/// The Chat page's calls to an instance's conversation proxy. Errors are `HomerAPIError`s; a
/// `.unauthorized` is a token the proxy does not know.
@DependencyClient
public struct HomerConversationsClient: Sendable {
	/// Who the token is: a check of the settings, and the author's name.
	public var me: @Sendable (_ proxy: HomerProxySettings) async throws -> HomerProxyUser
	/// The workflows a conversation can run.
	public var workflows: @Sendable (_ proxy: HomerProxySettings) async throws -> [HomerWorkflow]
	/// A page of conversations, newest activity first, from `cursor` on.
	public var conversations: @Sendable (_ proxy: HomerProxySettings, _ limit: Int, _ cursor: String?) async throws -> HomerConversationPage
	public var conversation: @Sendable (_ proxy: HomerProxySettings, _ id: String) async throws -> HomerConversationThread
	/// Starts a conversation with the workflow of `command` and `text` as the prompt.
	public var create: @Sendable (_ proxy: HomerProxySettings, _ command: String, _ text: String) async throws -> HomerConversationCreated
	/// Continues a conversation with `text`.
	public var reply: @Sendable (_ proxy: HomerProxySettings, _ id: String, _ text: String) async throws -> HomerConversationReply
	/// The proxy's live events, from `lastEventID` on; `.connected` first.
	public var events: @Sendable (_ proxy: HomerProxySettings, _ lastEventID: String?) -> AsyncThrowingStream<HomerConversationEvent, any Error> = { _, _ in
		AsyncThrowingStream { $0.finish() }
	}
}

extension HomerConversationsClient: DependencyKey {
	public static let liveValue = HomerConversationsClient(
		me: { try await HomerProxyAPI.me(proxy: $0) },
		workflows: { try await HomerProxyAPI.workflows(proxy: $0) },
		conversations: { try await HomerProxyAPI.conversations(proxy: $0, limit: $1, cursor: $2) },
		conversation: { try await HomerProxyAPI.conversation(proxy: $0, id: $1) },
		create: { try await HomerProxyAPI.createConversation(proxy: $0, command: $1, text: $2) },
		reply: { try await HomerProxyAPI.sendMessage(proxy: $0, id: $1, text: $2) },
		events: { HomerProxyAPI.events(proxy: $0, lastEventID: $1) }
	)
}

extension HomerConversationsClient: TestDependencyKey {
	public static let testValue = HomerConversationsClient()
}
