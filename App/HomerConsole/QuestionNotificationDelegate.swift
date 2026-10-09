import ComposableArchitecture
import HomerFeature
import UserNotifications

/// Notification Center's delegate for the console's question notifications. The package only
/// posts them; showing them while the app is frontmost and opening a clicked one are the
/// host's, as Bridge Commander has a delegate of its own.
final class QuestionNotificationDelegate: NSObject, UNUserNotificationCenterDelegate, Sendable {
	private let store: StoreOf<HomerConsoleReducer>

	init(store: StoreOf<HomerConsoleReducer>) {
		self.store = store
	}

	/// A click opens the instance's Questions page; the click itself brings the app forward.
	func userNotificationCenter(
		_ center: UNUserNotificationCenter,
		didReceive response: UNNotificationResponse
	) async {
		guard
			response.actionIdentifier == UNNotificationDefaultActionIdentifier,
			let instanceID = HomerQuestionNotification.instanceID(in: response.notification.request.content.userInfo)
		else {
			return
		}
		await store.send(.questionNotificationTapped(instanceID: instanceID))
	}

	/// Shown even while the app is frontmost: the console posts nothing for questions already on
	/// screen, and the question may belong to another instance or page.
	func userNotificationCenter(
		_ center: UNUserNotificationCenter,
		willPresent notification: UNNotification
	) async -> UNNotificationPresentationOptions {
		[.banner, .list, .sound]
	}
}
