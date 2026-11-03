import ComposableArchitecture
import DependenciesTestSupport
import Foundation
@testable import HomerContinuations
@testable import HomerCore
@testable import HomerFeature
import Testing

@MainActor
@Suite("Homer server uptime", .dependencies)
struct HomerServerStatusTests {
	private static let baseURL = "https://homer.example.com"

	private func activeState(_ user: HomerUser) -> HomerInstanceReducer.State {
		var state = HomerInstanceReducer.State(baseURL: Self.baseURL)
		state.session = .signedIn(user)
		return state
	}

	@Test("the server's state decodes: the start in epoch seconds as a string, its clock as an instant")
	func decodes() throws {
		let json = """
			{ "startTime": "1730000000", "currentTime": "2024-10-27T05:33:20.123456Z", "lastProcessId": 4596 }
			"""
		let status = try JSONDecoder().decode(HomerServerStatus.self, from: Data(json.utf8))

		#expect(status.startTime == 1_730_000_000)
		#expect(abs(status.currentTime - 1_730_007_200.123456) < 0.0001)
		#expect(status.lastProcessId == 4596)
		#expect(abs(status.uptime - 7200.123456) < 0.0001)
	}

	@Test("an instant reads with any fraction, or none")
	func instants() {
		#expect(HomerServerStatus.epochSeconds("2024-10-27T05:33:20Z") == 1_730_007_200)
		#expect(HomerServerStatus.epochSeconds("2024-10-27T05:33:20.5Z") == 1_730_007_200.5)
		#expect(HomerServerStatus.epochSeconds("2024-10-27T05:33:20.123456789Z").map { abs($0 - 1_730_007_200.123456789) < 0.000001 } == true)
		#expect(HomerServerStatus.epochSeconds("1730000000") == 1_730_000_000)
		#expect(HomerServerStatus.epochSeconds("yesterday") == nil)
	}

	@Test("the uptime reads in its two largest units")
	func uptimeText() {
		#expect(HomerServerStatus.uptimeText(40) == "Up 40s")
		#expect(HomerServerStatus.uptimeText(12 * 60 + 5) == "Up 12m")
		#expect(HomerServerStatus.uptimeText(4 * 3600 + 12 * 60) == "Up 4h 12m")
		#expect(HomerServerStatus.uptimeText(3 * 86400 + 4 * 3600 + 59) == "Up 3d 4h")
	}

	@Test("an admin's instance reads the server's start with each health poll and on Refresh; the uptime runs on from the read")
	func adminReads() async {
		let clock = TestClock()
		let reads = LockIsolated(0)
		let status = HomerServerStatus(startTime: 1_000, currentTime: 4_600, lastProcessId: 77)
		let readAt = Date(timeIntervalSince1970: 1_800_000_000)
		let store = TestStore(initialState: activeState(HomerUser(username: "admin", role: "admin"))) {
			HomerInstanceReducer()
		} withDependencies: {
			$0.continuousClock = clock
			$0.date.now = readAt
			$0[HomerServerStatusClient.self].status = { baseURL in
				#expect(baseURL == "https://homer.example.com")
				reads.withValue { $0 += 1 }
				return status
			}
			$0[HomerClient.self].processes = { _, _ in HomerProcessPage(processes: [], total: 0) }
			$0[HomerClient.self].agentNames = { _ in [] }
			$0[HomerClient.self].openQuestions = { _ in HomerQuestionPage(questions: []) }
			$0[HomerClient.self].health = { _ in HomerHealth(runners: []) }
			$0[HomerClient.self].version = { _ in "1.40.0" }
			$0[HomerContinuationsClient.self].pendingCount = { _ in 0 }
			$0[HomerClient.self].logout = { _ in }
		}
		store.exhaustivity = .off(showSkippedAssertions: false)

		await store.send(.activated)
		await store.receive(\.serverStatusLoaded) {
			$0.serverStatus = status
			$0.serverStatusReadAt = readAt
		}
		#expect(store.state.serverUptime(at: readAt.addingTimeInterval(60)) == 3_660)

		await clock.advance(by: HomerInstanceReducer.healthPollInterval)
		await store.receive(\.serverStatusLoaded)
		#expect(reads.value == 2)

		await store.send(.refreshTapped)
		await store.receive(\.serverStatusLoaded)
		#expect(reads.value == 3)

		// Signing out forgets it.
		await store.send(.signOutTapped) {
			$0.serverStatus = nil
			$0.serverStatusReadAt = nil
		}
	}

	@Test("anyone but an admin is never asked: the server answers them 403")
	func nonAdmin() async {
		let store = TestStore(initialState: activeState(HomerUser(username: "dev"))) {
			HomerInstanceReducer()
		} withDependencies: {
			$0.continuousClock = TestClock()
			// `HomerServerStatusClient` is left unimplemented: a call would fail the test.
			$0[HomerClient.self].processes = { _, _ in HomerProcessPage(processes: [], total: 0) }
			$0[HomerClient.self].agentNames = { _ in [] }
			$0[HomerClient.self].openQuestions = { _ in HomerQuestionPage(questions: []) }
			$0[HomerClient.self].health = { _ in HomerHealth(runners: []) }
			$0[HomerClient.self].version = { _ in "1.40.0" }
			$0[HomerContinuationsClient.self].pendingCount = { _ in 0 }
		}
		store.exhaustivity = .off(showSkippedAssertions: false)

		await store.send(.activated)
		await store.send(.refreshTapped)
		await store.skipInFlightEffects()
		#expect(store.state.serverStatus == nil)
	}

	@Test("the agent names reach the Continuations page's agent filter")
	func agentNamesReachContinuations() async {
		let store = TestStore(initialState: activeState(HomerUser(username: "dev"))) {
			HomerInstanceReducer()
		}

		await store.send(.agentNamesLoaded(.success(["deploy", "factory"]))) {
			$0.agentNames = ["deploy", "factory"]
			$0.continuations.agentNames = ["deploy", "factory"]
		}
	}
}
