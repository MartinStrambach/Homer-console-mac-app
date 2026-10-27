import ComposableArchitecture
import DependenciesTestSupport
import Foundation
@testable import HomerCore
@testable import HomerFeature
import Testing

@MainActor
@Suite("Homer maintenance mode", .dependencies)
struct HomerMaintenanceTests {
	private static let baseURL = "https://homer.example.com"

	private func signedInState(_ user: HomerUser, maintenance: Bool?) -> HomerInstanceReducer.State {
		var state = HomerInstanceReducer.State(baseURL: Self.baseURL)
		state.session = .signedIn(user)
		state.maintenance = maintenance
		return state
	}

	@Test("the mode's state decodes, with no start time while off or across a restart")
	func decodes() throws {
		let on = try JSONDecoder().decode(
			HomerMaintenance.self,
			from: Data(#"{"enabled":true,"since":1700000000,"queued":3}"#.utf8)
		)
		#expect(on == HomerMaintenance(enabled: true, since: 1_700_000_000, queued: 3))

		let off = try JSONDecoder().decode(HomerMaintenance.self, from: Data(#"{"enabled":false,"since":null}"#.utf8))
		#expect(off == HomerMaintenance(enabled: false))
	}

	@Test("an admin's health with the mode on reads since when and how many wait; off drops it")
	func adminReadsDetail() async {
		let detail = HomerMaintenance(enabled: true, since: 1_700_000_000, queued: 2)
		let store = TestStore(initialState: signedInState(HomerUser(username: "admin", role: "admin"), maintenance: nil)) {
			HomerInstanceReducer()
		} withDependencies: {
			$0[HomerMaintenanceClient.self].maintenance = { _ in detail }
		}

		await store.send(.healthLoaded(HomerHealth(runners: [], maintenance: true))) {
			$0.maintenance = true
		}
		await store.receive(\.maintenanceLoaded.success) {
			$0.maintenanceDetail = detail
		}
		await store.send(.healthLoaded(HomerHealth(runners: [], maintenance: false))) {
			$0.maintenance = false
			$0.maintenanceDetail = nil
		}
	}

	@Test("anyone else sees the banner without the admin's detail, and has no toggle")
	func nonAdmin() async {
		// No maintenance call: the client is unimplemented, so one would fail the test.
		let store = TestStore(initialState: signedInState(HomerUser(username: "dev"), maintenance: nil)) {
			HomerInstanceReducer()
		}

		await store.send(.healthLoaded(HomerHealth(runners: [], maintenance: true))) {
			$0.maintenance = true
		}
		await store.send(.maintenanceToggleTapped)
	}

	@Test("an admin turns the mode on once confirmed, and off again from the banner")
	func adminToggles() async {
		let sent = LockIsolated<[Bool]>([])
		let store = TestStore(initialState: signedInState(HomerUser(username: "admin", role: "admin"), maintenance: false)) {
			HomerInstanceReducer()
		} withDependencies: {
			$0[HomerMaintenanceClient.self].setMaintenance = { _, enabled in
				sent.withValue { $0.append(enabled) }
				return HomerMaintenance(enabled: enabled, since: enabled ? 1_700_000_000 : nil, queued: 0)
			}
		}

		await store.send(.maintenanceToggleTapped) {
			$0.alert = HomerInstanceReducer.turnOnMaintenanceAlert
		}
		await store.send(.alert(.presented(.maintenanceConfirmed(enabled: true)))) {
			$0.alert = nil
			$0.isSettingMaintenance = true
		}
		await store.receive(\.maintenanceSet) {
			$0.isSettingMaintenance = false
			$0.maintenance = true
			$0.maintenanceDetail = HomerMaintenance(enabled: true, since: 1_700_000_000)
		}

		await store.send(.maintenanceToggleTapped) {
			$0.alert = HomerInstanceReducer.turnOffMaintenanceAlert(queued: 0)
		}
		await store.send(.alert(.presented(.maintenanceConfirmed(enabled: false)))) {
			$0.alert = nil
			$0.isSettingMaintenance = true
		}
		await store.receive(\.maintenanceSet) {
			$0.isSettingMaintenance = false
			$0.maintenance = false
			$0.maintenanceDetail = nil
		}
		#expect(sent.value == [true, false])
	}

	@Test("a health read that lands while a toggle is under way does not put back the old mode")
	func healthDuringToggle() async {
		var state = signedInState(HomerUser(username: "admin", role: "admin"), maintenance: false)
		state.isSettingMaintenance = true
		let store = TestStore(initialState: state) {
			HomerInstanceReducer()
		}

		await store.send(.healthLoaded(HomerHealth(runners: [], maintenance: false)))
	}

	@Test("a refused toggle says why, and the mode stays as it was")
	func toggleFails() async {
		let refusal = HomerAPIError.server(status: 404, message: "No maintenance mode here.")
		let store = TestStore(initialState: signedInState(HomerUser(username: "admin", role: "admin"), maintenance: false)) {
			HomerInstanceReducer()
		} withDependencies: {
			$0[HomerMaintenanceClient.self].setMaintenance = { _, _ in throw refusal }
		}

		await store.send(.maintenanceToggleTapped) {
			$0.alert = HomerInstanceReducer.turnOnMaintenanceAlert
		}
		await store.send(.alert(.presented(.maintenanceConfirmed(enabled: true)))) {
			$0.alert = nil
			$0.isSettingMaintenance = true
		}
		await store.receive(\.maintenanceSet) {
			$0.isSettingMaintenance = false
			$0.alert = AlertState {
				TextState("Could Not Turn On Maintenance Mode")
			} actions: {
				ButtonState(role: .cancel) {
					TextState("OK")
				}
			} message: {
				TextState("No maintenance mode here.")
			}
		}
	}

	@Test("a server that predates the mode offers no toggle")
	func olderServer() async {
		let store = TestStore(initialState: signedInState(HomerUser(username: "admin", role: "admin"), maintenance: nil)) {
			HomerInstanceReducer()
		}

		await store.send(.healthLoaded(HomerHealth(runners: [])))
		await store.send(.maintenanceToggleTapped)
	}
}
