import Foundation
@testable import HomerConversations
@testable import HomerCore
import Testing

@Suite("Homer conversation models")
struct HomerConversationModelsTests {
	/// A page of `GET /conversations`, as the proxy's README gives it, with a field this version
	/// does not read left in.
	private let pageJSON = """
		{
		  "items": [
		    {
		      "id": "1758445123.123456",
		      "origin": "slack",
		      "workflowCommand": "",
		      "agent": "conversation",
		      "slackChannel": "C0123456789",
		      "slackTeam": "T0123",
		      "title": "is the login flow covered by tests?",
		      "createdAt": 1758445123.5,
		      "updatedAt": 1758445200,
		      "inFlight": true,
		      "runCount": 2,
		      "lastMessage": { "role": "assistant", "author": "conversation", "preview": "Mostly.", "createdAt": 1758445200 },
		      "someNewField": 1
		    },
		    {
		      "id": "app-5f1a",
		      "origin": "telepathy",
		      "workflowCommand": "ask",
		      "agent": "ask-web",
		      "title": "hello",
		      "createdAt": 1758445000,
		      "updatedAt": 1758445000,
		      "inFlight": false,
		      "runCount": 1
		    }
		  ],
		  "nextCursor": "1758445000:app-5f1a"
		}
		"""

	private let threadJSON = """
		{
		  "conversation": {
		    "id": "app-5f1a", "origin": "app", "workflowCommand": "", "agent": "conversation", "title": "hello",
		    "createdAt": 1758445000, "updatedAt": 1758445060, "inFlight": false, "runCount": 1
		  },
		  "messages": [
		    { "id": 1, "conversationId": "app-5f1a", "runId": 1, "role": "user", "author": "martin", "text": "hello", "createdAt": 1758445000 },
		    { "id": 2, "conversationId": "app-5f1a", "runId": 1, "role": "assistant", "author": "conversation", "text": "Hi *there*", "createdAt": 1758445060 },
		    { "id": 3, "conversationId": "app-5f1a", "role": "narrator", "author": "proxy", "text": "?", "createdAt": 1758445061 }
		  ],
		  "runs": [
		    {
		      "id": 1, "conversationId": "app-5f1a", "origin": "app", "startedBy": "martin", "agent": "conversation",
		      "workflowCommand": "", "rootProcessId": 412, "currentProcessId": 415, "processIds": [412, 415],
		      "state": "finished", "homerStatus": "FINISHED", "costUsd": 0.38, "openQuestions": 0,
		      "startedAt": 1758445000, "endedAt": 1758445060, "updatedAt": 1758445060
		    },
		    {
		      "id": 2, "conversationId": "app-5f1a", "origin": "slack", "startedBy": "slack:C01", "agent": "conversation",
		      "workflowCommand": "", "processIds": [], "state": "parked", "errorText": "continuation expired",
		      "startedAt": 1758445100, "updatedAt": 1758445100
		    },
		    {
		      "id": 3, "conversationId": "app-5f1a", "origin": "app", "startedBy": "martin", "agent": "conversation",
		      "workflowCommand": "", "processIds": [500], "state": "sideways",
		      "startedAt": 1758445200, "updatedAt": 1758445200
		    }
		  ]
		}
		"""

	@Test("a page decodes with its cursor; an unknown origin reads as unknown")
	func page() throws {
		let page = try JSONDecoder().decode(HomerConversationPage.self, from: Data(pageJSON.utf8))

		#expect(page.nextCursor == "1758445000:app-5f1a")
		#expect(page.items.map(\.id) == ["1758445123.123456", "app-5f1a"])
		let slack = try #require(page.items.first)
		#expect(slack.origin == .slack)
		#expect(slack.slackChannel == "C0123456789")
		#expect(slack.inFlight)
		#expect(slack.lastMessage?.role == .assistant)
		#expect(slack.lastMessage?.preview == "Mostly.")
		#expect(page.items[1].origin == .unknown)
		#expect(page.items[1].lastMessage == nil)
	}

	@Test("a thread decodes its messages and runs; unknown roles and states read as unknown")
	func thread() throws {
		let thread = try JSONDecoder().decode(HomerConversationThread.self, from: Data(threadJSON.utf8))

		#expect(thread.conversation.id == "app-5f1a")
		#expect(thread.messages.map(\.role) == [.user, .assistant, .unknown])
		#expect(thread.messages[0].runId == 1)
		#expect(thread.messages[2].runId == nil)

		let finished = thread.runs[0]
		#expect(finished.state == .finished)
		#expect(finished.processIds == [412, 415])
		#expect(finished.homerStatus == .finished)
		#expect(finished.costUsd == 0.38)
		#expect(finished.state.processStatus == .finished)
		#expect(!finished.state.isActive)

		let parked = thread.runs[1]
		#expect(parked.state == .parked)
		#expect(parked.state.processStatus == nil)
		#expect(parked.rootProcessId == nil)
		#expect(parked.errorText == "continuation expired")

		#expect(thread.runs[2].state == .unknown)
	}

	@Test("a run's state maps onto Homer's statuses where it is one")
	func runStates() {
		#expect(HomerConversationRun.State.queued.processStatus == .created)
		#expect(HomerConversationRun.State.running.processStatus == .working)
		#expect(HomerConversationRun.State.running.isActive)
		#expect(HomerConversationRun.State.waitingResume.isActive)
		#expect(HomerConversationRun.State.waitingResume.processStatus == nil)
		#expect(HomerConversationRun.State.timeout.processStatus == nil)
		#expect(HomerConversationRun.State.killed.processStatus == .killed)
	}

	@Test("the proxy's events decode by name, carrying the event's id; unknown ones are skipped")
	func events() throws {
		let conversation = HomerServerSentEvent(
			name: "conversation.updated",
			id: "42",
			data: #"{"id":"app-1","origin":"app","workflowCommand":"","agent":"a","title":"t","createdAt":1,"updatedAt":2,"inFlight":false,"runCount":1}"#
		)
		let updated = try #require(HomerConversationEvent(conversation))
		#expect(updated.id == "42")
		guard case let .conversationUpdated(value) = updated.kind else {
			Issue.record("not a conversation update")
			return
		}
		#expect(value.id == "app-1")

		let created = try #require(HomerConversationEvent(HomerServerSentEvent(name: "conversation.created", id: "43", data: conversation.data)))
		guard case .conversationCreated = created.kind else {
			Issue.record("not a conversation creation")
			return
		}

		let message = HomerServerSentEvent(
			name: "message.created",
			id: "44",
			data: #"{"id":7,"conversationId":"app-1","role":"user","author":"martin","text":"hi","createdAt":3}"#
		)
		guard case let .messageCreated(value) = try #require(HomerConversationEvent(message)).kind else {
			Issue.record("not a message")
			return
		}
		#expect(value.id == 7)

		let run = HomerServerSentEvent(
			name: "run.updated",
			id: "45",
			data: #"{"id":1,"conversationId":"app-1","origin":"app","startedBy":"martin","agent":"a","workflowCommand":"","processIds":[9],"state":"running","startedAt":1,"updatedAt":2}"#
		)
		guard case let .runUpdated(value) = try #require(HomerConversationEvent(run)).kind else {
			Issue.record("not a run")
			return
		}
		#expect(value.state == .running)

		#expect(HomerConversationEvent(HomerServerSentEvent(name: "reset", id: nil, data: "{}"))?.kind == .reset)
		#expect(HomerConversationEvent(HomerServerSentEvent(name: "something.else", id: "1", data: "{}")) == nil)
		#expect(HomerConversationEvent(HomerServerSentEvent(name: "run.updated", id: "1", data: "not json")) == nil)
	}

	@Test("a workflow's title names the default by its agent")
	func workflowTitle() throws {
		let workflows = try JSONDecoder().decode(
			[HomerWorkflow].self,
			from: Data(#"[{"command":"","agent":"conversation","description":"Chat","followUps":"mention"},{"command":"ask","agent":"ask-web","description":""}]"#.utf8)
		)
		#expect(workflows[0].isDefault)
		#expect(workflows[0].title == "Default (conversation)")
		#expect(workflows[1].title == "ask")
		#expect(workflows[1].followUps == nil)
	}
}
