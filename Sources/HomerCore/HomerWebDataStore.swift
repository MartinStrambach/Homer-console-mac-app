import Foundation
import WebKit

/// The embedded web console's data store of each instance (`HomerEndpoint.webDataStoreID`):
/// apart from one another, like the instances' cookie jars, so two instances on one host do not
/// sign each other's pages out.
@MainActor
package enum HomerWebDataStore {
	package static func store(id: UUID) -> WKWebsiteDataStore {
		WKWebsiteDataStore(forIdentifier: id)
	}

	/// Signs the embedded console out with the app: its copy of the session cookie would
	/// otherwise stay valid there until it expires.
	static func removeCookies(baseURL: String) async {
		await store(id: HomerEndpoint.webDataStoreID(baseURL: baseURL))
			.removeData(ofTypes: [WKWebsiteDataTypeCookies], modifiedSince: .distantPast)
	}
}
