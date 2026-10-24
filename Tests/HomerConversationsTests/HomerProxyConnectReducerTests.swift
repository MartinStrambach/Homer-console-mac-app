import ComposableArchitecture
import DependenciesTestSupport
import Foundation
@testable import HomerConversations
@testable import HomerCore
import Testing

@MainActor
@Suite("Homer proxy connect form", .dependencies)
struct HomerProxyConnectReducerTests {
	@Test("Connect normalizes the URL, trims the token, checks them with /me and hands them over")
	func connects() async {
		let asked = LockIsolated<HomerProxySettings?>(nil)
		let store = TestStore(initialState: HomerProxyConnectReducer.State(url: "proxy.example.com/", token: " secret ")) {
			HomerProxyConnectReducer()
		} withDependencies: {
			$0[HomerConversationsClient.self].me = { proxy in
				asked.setValue(proxy)
				return HomerProxyUser(name: "martin")
			}
		}
		let settings = HomerProxySettings(url: "https://proxy.example.com", token: "secret")

		await store.send(.connectTapped) {
			$0.isConnecting = true
		}
		await store.receive(\.connectFinished) {
			$0.isConnecting = false
			$0.url = "https://proxy.example.com"
		}
		await store.receive(\.delegate, .connected(settings, name: "martin"))
		#expect(asked.value == settings)
	}

	@Test("a token the proxy does not know is said so; another failure in its own words")
	func failures() async {
		let error = LockIsolated<any Error>(HomerAPIError.unauthorized)
		let store = TestStore(initialState: HomerProxyConnectReducer.State(url: "https://proxy.example.com", token: "nope")) {
			HomerProxyConnectReducer()
		} withDependencies: {
			$0[HomerConversationsClient.self].me = { _ in throw error.value }
		}

		await store.send(.connectTapped) {
			$0.isConnecting = true
		}
		await store.receive(\.connectFinished) {
			$0.isConnecting = false
			$0.error = HomerProxyConnectReducer.unknownTokenMessage
		}

		error.setValue(HomerAPIError.unreachable("refused"))
		await store.send(.connectTapped) {
			$0.isConnecting = true
			$0.error = nil
		}
		await store.receive(\.connectFinished) {
			$0.isConnecting = false
			$0.error = "Could not reach the server: refused"
		}
	}

	@Test("blank fields and a bad URL never reach the proxy")
	func refuses() async {
		var state = HomerProxyConnectReducer.State(url: "", token: "secret")
		#expect(!state.canConnect)
		state.url = "ftp://proxy"
		#expect(state.canConnect)
		let store = TestStore(initialState: state) {
			HomerProxyConnectReducer()
		}

		await store.send(.connectTapped) {
			$0.error = HomerProxyConnectReducer.invalidURLMessage
		}
		await store.send(.binding(.set(\.token, ""))) {
			$0.token = ""
		}
		await store.send(.connectTapped)
	}
}
