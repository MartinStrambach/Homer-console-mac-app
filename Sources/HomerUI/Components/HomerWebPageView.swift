import HomerCore
import SwiftUI
import WebKit

/// A page of the web console in a sheet — what the app does not show natively: an agent's page,
/// the file editor, a run's workflow graph, or any page from the header's Safari button. The
/// app's session cookies are copied into the instance's own web data store
/// (`HomerWebDataStore`) before the page loads, so it opens signed in; if they are missing or
/// stale the console shows its own sign-in page, which works as well.
///
/// Loaded as the top-level page, not in a frame: the console sends `X-Frame-Options: DENY` and
/// `frame-ancestors 'none'`, which only an embedding `<iframe>` would trip over.
package struct HomerWebPageView: View {
	let page: HomerWebPage

	@State
	private var webPage: WebPage

	@Environment(\.dismiss)
	private var dismiss

	@Environment(\.openURL)
	private var openURL

	package init(page: HomerWebPage) {
		self.page = page
		var configuration = WebPage.Configuration()
		configuration.websiteDataStore = HomerWebDataStore.store(id: page.dataStoreID)
		_webPage = State(initialValue: WebPage(configuration: configuration))
	}

	package var body: some View {
		VStack(spacing: 0) {
			HStack(spacing: 10) {
				Text(page.title)
					.scaledFont(.headline)
				if webPage.isLoading {
					ProgressView()
						.controlSize(.small)
				}
				Spacer()
				Button("Open in Browser") {
					openURL(webPage.url ?? page.url)
				}
				.buttonStyle(.scaledBordered)
				Button("Done") { dismiss() }
					.buttonStyle(.scaledBorderedProminent)
					.keyboardShortcut(.cancelAction)
			}
			.padding(12)

			Divider()

			WebView(webPage)
		}
		.frame(minWidth: 900, idealWidth: 1200, minHeight: 600, idealHeight: 800)
		.task {
			let cookieStore = HomerWebDataStore.store(id: page.dataStoreID).httpCookieStore
			for cookie in page.cookies {
				await cookieStore.setCookie(cookie)
			}
			webPage.load(URLRequest(url: page.url))
		}
	}
}
