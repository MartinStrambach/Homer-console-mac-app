import Foundation

/// A page of the web console opened in the embedded browser sheet, with the session cookies it
/// needs to open signed in and the instance's own web data store to open it in.
public struct HomerWebPage: Equatable, Identifiable {
	public let url: URL
	public let title: String
	package let cookies: [HTTPCookie]
	package let dataStoreID: UUID

	public var id: URL {
		url
	}
}

extension HomerWebPage {
	/// A page of the instance's web console, e.g. `processes/42`, opened with the session the
	/// app holds for it.
	package init?(baseURL: String, path: String, title: String, cookies: [HTTPCookie]) {
		guard let url = HomerEndpoint.pageURL(baseURL: baseURL, path: path) else {
			return nil
		}
		self.url = url
		self.title = title
		self.cookies = cookies
		self.dataStoreID = HomerEndpoint.webDataStoreID(baseURL: baseURL)
	}
}
