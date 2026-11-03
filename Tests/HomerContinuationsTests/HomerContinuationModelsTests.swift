import Foundation
@testable import HomerCore
@testable import HomerContinuations
import Testing

@Suite("Homer continuation models")
struct HomerContinuationModelsTests {
	/// The backend's `ContinuationListResponse`, shaped like the console's test fixture
	/// (`continuation-item.test.tsx`), with the fields the app does not read left in.
	private let listJSON = """
		{
		  "continuations": [
		    {
		      "id": 5,
		      "watchedProcessId": 12,
		      "status": "PENDING",
		      "agentName": "follow-up",
		      "resumeParam": "RESULT",
		      "params": { "TICKET": "MOB-1234", "TOKEN": "***" },
		      "originProcessId": 7,
		      "originAgentName": "starter",
		      "expiresAt": 1700086400,
		      "createdAt": 1700000000,
		      "firedAt": null,
		      "firedProcessId": null,
		      "error": null
		    },
		    {
		      "id": 6,
		      "watchedProcessId": 13,
		      "status": "FAILED",
		      "agentName": "crash-report",
		      "resumeParam": "RESULT",
		      "params": {},
		      "originProcessId": 8,
		      "originAgentName": "factory",
		      "createdAt": 1700000100,
		      "error": "Agent not found: crash-report"
		    },
		    {
		      "id": 7,
		      "watchedProcessId": 14,
		      "status": "DISPATCHED",
		      "agentName": "follow-up",
		      "resumeParam": "RESULT",
		      "params": {},
		      "originProcessId": 9,
		      "originAgentName": "starter",
		      "createdAt": 1700000200,
		      "firedAt": 1700000300,
		      "firedProcessId": 99
		    },
		    {
		      "id": 8,
		      "watchedProcessId": 15,
		      "status": "PARKED_BY_A_NEWER_SERVER",
		      "agentName": "follow-up",
		      "resumeParam": "RESULT",
		      "params": {},
		      "originProcessId": 10,
		      "originAgentName": "starter",
		      "createdAt": 1700000400
		    }
		  ]
		}
		"""

	@Test("a continuation list decodes, unknown fields and statuses included")
	func decodesList() throws {
		let list = try JSONDecoder().decode(HomerContinuationList.self, from: Data(listJSON.utf8))

		#expect(list.continuations.map(\.id) == [5, 6, 7, 8])
		#expect(list.continuations.map(\.status) == [.pending, .failed, .dispatched, .unknown])
		#expect(list.continuations[0] == HomerContinuation(
			id: 5,
			watchedProcessId: 12,
			status: .pending,
			agentName: "follow-up",
			originProcessId: 7,
			originAgentName: "starter",
			expiresAt: 1_700_086_400,
			createdAt: 1_700_000_000,
			resumeParam: "RESULT",
			params: ["TICKET": "MOB-1234", "TOKEN": "***"]
		))
		#expect(list.continuations[1].error == "Agent not found: crash-report")
		#expect(list.continuations[1].expiresAt == nil)
		#expect(list.continuations[2].firedProcessId == 99)
		#expect(list.continuations[2].firedAt == 1_700_000_300)
	}

	@Test("only a pending continuation offers Cancel")
	func cancellable() {
		let cancellable = HomerContinuationStatus.allCases.filter {
			HomerContinuation(
				id: 1,
				watchedProcessId: 2,
				status: $0,
				agentName: "a",
				originProcessId: 3,
				originAgentName: "b",
				createdAt: 0
			).isCancellable
		}

		#expect(cancellable == [.pending])
	}

	@Test("a run link in a card's text reads back as its process id")
	func processLink() throws {
		let url = try #require(HomerRunLink.processURL(42))

		#expect(HomerRunLink.processId(from: url) == 42)
		#expect(HomerRunLink.processId(from: URL(string: "https://homer.example.com/processes/42")!) == nil)
	}

	@Test("a stale cancel reads as the list's message, anything else as itself")
	func cancelErrors() {
		#expect(HomerContinuationListReducer.cancelErrorMessage(HomerAPIError.conflict)
			== HomerContinuationKind.notCancellableMessage)
		#expect(HomerDispatchListReducer.cancelErrorMessage(HomerAPIError.server(status: 404, message: "Not found"))
			== HomerDispatchKind.notCancellableMessage)
		#expect(HomerContinuationListReducer.cancelErrorMessage(HomerAPIError.forbidden)
			== HomerAPIError.forbidden.localizedDescription)
	}

	@Test("a dispatch list decodes, unknown fields and statuses included")
	func decodesDispatches() throws {
		let json = """
			{
			  "dispatches": [
			    {
			      "id": 3,
			      "questionId": "q-1",
			      "status": "PENDING",
			      "agentName": "deploy",
			      "answerParam": "APPROVAL",
			      "params": { "ENV": "prod" },
			      "originProcessId": 40,
			      "originAgentName": "release",
			      "expiresAt": 1700003600,
			      "createdAt": 1700000000,
			      "dispatchedAt": null,
			      "dispatchedProcessId": null,
			      "error": null
			    },
			    {
			      "id": 4,
			      "questionId": "q-2",
			      "status": "FAILED",
			      "agentName": "deploy",
			      "answerParam": "APPROVAL",
			      "params": {},
			      "originProcessId": 41,
			      "originAgentName": "release",
			      "createdAt": 1700000100,
			      "dispatchedAt": 1700000200,
			      "error": "agent 'deploy' not found"
			    },
			    {
			      "id": 5,
			      "questionId": "q-3",
			      "status": "SOMETHING_NEWER",
			      "agentName": "deploy",
			      "answerParam": "APPROVAL",
			      "params": {},
			      "originProcessId": 42,
			      "originAgentName": "release",
			      "createdAt": 1700000300
			    }
			  ],
			  "total": 12,
			  "offset": 0,
			  "limit": 100
			}
			"""
		let list = try JSONDecoder().decode(HomerDispatchList.self, from: Data(json.utf8))

		#expect(list.total == 12)
		#expect(list.dispatches.map(\.status) == [.pending, .failed, .unknown])
		#expect(list.dispatches[0] == HomerDispatch(
			id: 3,
			questionId: "q-1",
			status: .pending,
			agentName: "deploy",
			answerParam: "APPROVAL",
			params: ["ENV": "prod"],
			originProcessId: 40,
			originAgentName: "release",
			expiresAt: 1_700_003_600,
			createdAt: 1_700_000_000
		))
		#expect(list.dispatches[1].error == "agent 'deploy' not found")
		#expect(list.dispatches.map(\.isCancellable) == [true, false, false])
	}

	@Test("a list query sends only the filters set")
	func queryItems() {
		#expect(HomerRecordQuery<HomerDispatchStatus>().queryItems == [URLQueryItem(name: "limit", value: "100")])
		#expect(HomerRecordQuery<HomerContinuationStatus>(status: .expired, agentName: "follow-up", limit: 200).queryItems == [
			URLQueryItem(name: "limit", value: "200"),
			URLQueryItem(name: "status", value: "EXPIRED"),
			URLQueryItem(name: "agentName", value: "follow-up"),
		])
	}

	@Test("a pending record expires soon within the hour, or once past its time; anything else never")
	func expiringSoon() {
		let now = Date(timeIntervalSince1970: 1_700_000_000)
		func dispatch(_ status: HomerDispatchStatus, expiresIn seconds: Double?) -> HomerDispatch {
			HomerDispatch(
				id: 1,
				questionId: "q",
				status: status,
				agentName: "a",
				originProcessId: 1,
				originAgentName: "o",
				expiresAt: seconds.map { now.timeIntervalSince1970 + $0 },
				createdAt: 0
			)
		}

		#expect(dispatch(.pending, expiresIn: 59 * 60).isExpiringSoon(now: now))
		#expect(dispatch(.pending, expiresIn: -10).isExpiringSoon(now: now))
		#expect(!dispatch(.pending, expiresIn: 61 * 60).isExpiringSoon(now: now))
		#expect(!dispatch(.pending, expiresIn: nil).isExpiringSoon(now: now))
		#expect(!dispatch(.failed, expiresIn: 60).isExpiringSoon(now: now))
	}

	@Test("a page's total is never below what it holds")
	func pageTotal() {
		let continuation = HomerContinuation(
			id: 1, watchedProcessId: 2, status: .pending, agentName: "a", originProcessId: 3, originAgentName: "b", createdAt: 0
		)

		#expect(HomerRecordPage(items: [continuation]).total == 1)
		#expect(HomerRecordPage(items: [continuation], total: 0).total == 1)
		#expect(HomerRecordPage(items: [continuation], total: 40).total == 40)
	}
}
