import ComposableArchitecture
import DependenciesTestSupport
import Foundation
@testable import HomerCore
@testable import HomerRunners
import Testing

@MainActor
@Suite("Homer runners page", .dependencies)
struct HomerRunnersReducerTests {
	private static let baseURL = "https://homer.example.com"

	private let runners = HomerRunners(runners: [
		HomerRunner(alias: "k8s", kind: "kubernetes", tags: ["gpu"], concurrency: 8, inUse: 2),
	])
	private let queue = HomerRunnerQueue(
		pending: 1,
		oldestAgeSec: 12,
		byFilter: [.init(filter: .init(alias: "k8s"), pending: 1, oldestAgeSec: 12)]
	)

	/// Lets the effects started so far deliver their answers, then takes them in.
	private func settle(_ store: TestStoreOf<HomerRunnersReducer>) async {
		for _ in 0 ..< 10 {
			await Task.yield()
		}
		await store.skipReceivedActions(strict: false)
	}

	@Test("coming on screen loads both, then polls them every 5 s until hidden")
	func shownPollsUntilHidden() async {
		let clock = TestClock()
		let calls = LockIsolated<[String]>([])
		let expectedCalls = ["queue", "runners \(Self.baseURL)"]
		let store = TestStore(initialState: HomerRunnersReducer.State(baseURL: Self.baseURL)) {
			HomerRunnersReducer()
		} withDependencies: {
			$0.continuousClock = clock
			$0[HomerRunnersClient.self].runners = { [runners] baseURL in
				calls.withValue { $0.append("runners \(baseURL)") }
				return runners
			}
			$0[HomerRunnersClient.self].queue = { [queue] _ in
				calls.withValue { $0.append("queue") }
				return queue
			}
		}

		// The two loops start together, and which answers first is the scheduler's business.
		store.exhaustivity = .off(showSkippedAssertions: false)
		await store.send(.shown) {
			$0.isShown = true
		}
		await settle(store)
		#expect(store.state.runners == runners)
		#expect(store.state.queue == queue)
		#expect(store.state.isLoading == false)
		#expect(calls.value.sorted() == expectedCalls)

		calls.setValue([])
		await clock.advance(by: .seconds(5))
		await settle(store)
		#expect(calls.value.sorted() == expectedCalls)

		// Shown twice (the instance re-syncing) starts no second pair of loops.
		calls.setValue([])
		await store.send(.shown)
		await clock.advance(by: .seconds(5))
		await settle(store)
		#expect(calls.value.count == 2)
		store.exhaustivity = .on

		// Exhaustive again: the test fails if a loop is still running when it ends.
		await store.send(.hidden) {
			$0.isShown = false
		}
		calls.setValue([])
		await clock.advance(by: .seconds(30))
		#expect(calls.value.isEmpty)
	}

	@Test("a failed refresh keeps the last data under one banner, until the next one succeeds")
	func failedRefreshKeepsData() async {
		let clock = TestClock()
		let failing = LockIsolated(true)
		var initialState = HomerRunnersReducer.State(baseURL: Self.baseURL)
		initialState.runners = runners
		initialState.queue = queue
		let store = TestStore(initialState: initialState) {
			HomerRunnersReducer()
		} withDependencies: { [runners, queue] in
			$0.continuousClock = clock
			$0[HomerRunnersClient.self].runners = { _ in
				if failing.value {
					throw HomerAPIError.unreachable("offline")
				}
				return runners
			}
			$0[HomerRunnersClient.self].queue = { _ in
				if failing.value {
					throw HomerAPIError.unreachable("offline")
				}
				return queue
			}
		}
		let message = HomerAPIError.unreachable("offline").localizedDescription

		store.exhaustivity = .off(showSkippedAssertions: false)
		await store.send(.shown) {
			$0.isShown = true
		}
		await settle(store)
		#expect(store.state.runnersError == message)
		#expect(store.state.queueError == message)
		#expect(store.state.errorMessages == [message])
		#expect(store.state.runners == runners)
		#expect(store.state.queue == queue)

		failing.setValue(false)
		await clock.advance(by: .seconds(5))
		await settle(store)
		#expect(store.state.errorMessages.isEmpty)
		store.exhaustivity = .on

		await store.send(.hidden) {
			$0.isShown = false
		}
	}

	@Test("a 401 stops the page and tells the instance its session ended")
	func unauthorized() async {
		let store = TestStore(initialState: HomerRunnersReducer.State(baseURL: Self.baseURL)) {
			HomerRunnersReducer()
		} withDependencies: {
			$0.continuousClock = TestClock()
			$0[HomerRunnersClient.self].runners = { _ in throw HomerAPIError.unauthorized }
			// The queue never answers before the page is stopped.
			$0[HomerRunnersClient.self].queue = { _ in
				try await Task.never()
			}
		}

		await store.send(.shown) {
			$0.isShown = true
		}
		await store.receive(\.runnersLoaded) {
			$0.isShown = false
		}
		await store.receive(\.delegate)
	}

	@Test("Refresh does nothing while the page is off screen")
	func refreshWhileHidden() async {
		let store = TestStore(initialState: HomerRunnersReducer.State(baseURL: Self.baseURL)) {
			HomerRunnersReducer()
		}

		await store.send(.refreshTapped)
	}
}
