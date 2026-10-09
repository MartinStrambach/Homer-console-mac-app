import Foundation
@testable import HomerCore
import Testing

@Suite("Homer API models")
struct HomerModelsTests {
	/// Trimmed from a real `/api/v1/status/all` answer, with fields the app does not read left in
	/// to show they are ignored.
	private let processPageJSON = """
		{
		  "processes": [
		    {
		      "id": 12345,
		      "status": "WORKING",
		      "agentName": "factory",
		      "owner": "admin",
		      "history": [
		        { "timestamp": 1700000000, "status": "CREATED" },
		        { "timestamp": 1700000100, "status": "WORKING" }
		      ],
		      "executions": [
		        { "label": "checkout", "start": 1700000050, "end": 1700000090, "resultCode": 0,
		          "stdOut": null, "stdErr": null, "errMsg": null, "kind": "cmd" }
		      ],
		      "currentCommand": "develop",
		      "currentCommandStart": 1700000095,
		      "purgeAt": null,
		      "runner": { "alias": null, "type": "kubernetes", "podPhase": "RUNNING" },
		      "openQuestions": 1,
		      "costUsd": 0.4211,
		      "costSource": "cli",
		      "parentProcessId": null,
		      "rootProcessId": null,
		      "tags": ["ticket:MOB-1234"]
		    },
		    {
		      "id": 12344,
		      "status": "PAUSED_BY_A_NEWER_SERVER",
		      "agentName": "factory-notify",
		      "history": [],
		      "executions": [],
		      "currentCommand": null,
		      "currentCommandStart": null,
		      "purgeAt": 1700009999
		    }
		  ],
		  "total": 150,
		  "offset": 0,
		  "limit": 50
		}
		"""

	@Test("a process page decodes, unknown fields and statuses included")
	func decodesProcessPage() throws {
		let page = try JSONDecoder().decode(HomerProcessPage.self, from: Data(processPageJSON.utf8))

		#expect(page.total == 150)
		#expect(page.processes.map(\.id) == [12345, 12344])
		let first = try #require(page.processes.first)
		#expect(first.status == .working)
		#expect(first.openQuestions == 1)
		#expect(first.tags == ["ticket:MOB-1234"])
		#expect(first.statusDate == Date(timeIntervalSince1970: 1_700_000_100))
		#expect(page.processes.last?.status == .unknown)
	}

	@Test("a working process reports its running command")
	func runningCommand() {
		let process = HomerProcess(id: 1, status: .working, agentName: "a", currentCommand: "build")

		#expect(process.lastCommand?.outcome == .running)
		#expect(process.lastCommand?.label == "build")
	}

	@Test("a finished process reports its last execution's outcome")
	func lastExecution() {
		var process = HomerProcess(
			id: 1,
			status: .failed,
			agentName: "a",
			executions: [.init(label: "build", resultCode: 0), .init(label: "test", resultCode: 2)]
		)
		#expect(process.lastCommand?.outcome == .failed)
		#expect(process.lastCommand?.label == "test")

		process.executions.append(.init(label: "notify", resultCode: 0, skipped: true))
		#expect(process.lastCommand?.outcome == .skipped)

		process.executions = []
		#expect(process.lastCommand == nil)
	}

	@Test("questions decode with their options and dispatch")
	func decodesQuestions() throws {
		let json = """
			{ "questions": [
			  { "id": "q-1", "processId": 7, "agentName": "factory", "text": "Ship **MOB-1**?",
			    "options": ["Yes", "No"], "status": "OPEN", "answer": null,
			    "createdAt": 1700000000, "answeredAt": null,
			    "dispatch": { "id": 3, "agentName": "factory-developer", "status": "PENDING" } }
			] }
			"""

		let questions = try JSONDecoder().decode(HomerQuestionList.self, from: Data(json.utf8)).questions

		#expect(questions == [
			HomerQuestion(
				id: "q-1",
				processId: 7,
				agentName: "factory",
				text: "Ship **MOB-1**?",
				options: ["Yes", "No"],
				createdAt: 1_700_000_000,
				dispatch: .init(id: 3, agentName: "factory-developer", status: "PENDING")
			),
		])
	}

	@Test("an answered question decodes its answer and what its dispatch started or why it failed")
	func decodesAnsweredQuestions() throws {
		let json = """
			{ "questions": [
			  { "id": "q-1", "processId": 7, "agentName": "factory", "text": "Ship?", "options": [],
			    "status": "ANSWERED", "answer": "Yes", "createdAt": 1700000000, "answeredAt": 1700000060,
			    "dispatch": { "id": 3, "agentName": "factory-developer", "status": "DISPATCHED",
			                  "dispatchedProcessId": 99, "error": null } },
			  { "id": "q-2", "processId": 7, "agentName": "factory", "text": "Deploy?", "options": [],
			    "status": "ANSWERED", "answer": "No", "createdAt": 1700000000, "answeredAt": 1700000090,
			    "dispatch": { "id": 4, "agentName": "deployer", "status": "FAILED", "error": "Cost cap reached" } }
			] }
			"""

		let questions = try JSONDecoder().decode(HomerQuestionList.self, from: Data(json.utf8)).questions

		#expect(questions.map(\.status) == [.answered, .answered])
		#expect(questions.map(\.answeredAt) == [1_700_000_060, 1_700_000_090])
		#expect(questions.map(\.dispatch?.startedProcessId) == [99, nil])
		#expect(questions.map(\.dispatch?.hasFailed) == [false, true])
		#expect(questions[1].dispatch?.error == "Cost cap reached")
	}
}
