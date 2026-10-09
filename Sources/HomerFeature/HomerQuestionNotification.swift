import AppKit
import ComposableArchitecture
import Foundation
import HomerCore
import UserNotifications

/// A question that opened while the console was running, as Notification Center shows it. Its
/// `userInfo` names the instance, so the host's notification delegate can hand a click back as
/// `HomerConsoleReducer.Action.questionNotificationTapped`.
public struct HomerQuestionNotification: Equatable, Sendable {
	static let instanceKey = "homerInstance"

	let instanceID: String
	let question: HomerQuestion
	/// Set when there is more than one instance, so the notification says which one asks.
	let instanceName: String?

	/// The instance a clicked question notification belongs to; nil for any other notification
	/// the host posts.
	public static func instanceID(in userInfo: [AnyHashable: Any]) -> String? {
		userInfo[instanceKey] as? String
	}

	/// One per question: posting it again replaces it rather than stacking.
	var identifier: String {
		"\(instanceID)#question-\(question.id)"
	}

	var title: String {
		"\(question.agentName) asks"
	}

	var subtitle: String {
		["Run #\(question.processId)", instanceName].compactMap(\.self).joined(separator: " · ")
	}

	/// The question's Markdown as plain text: Notification Center shows no formatting.
	var body: String {
		String(HomerQuestionCard.markdown(question.text).characters)
	}
}

/// Posts new questions to Notification Center. Only posts: the notification center's delegate
/// is the host's — Bridge Commander has its own for its terminal notifications — so presenting
/// a banner while the app is frontmost and handling a click are the host's to do.
@DependencyClient
struct HomerNotificationClient: Sendable {
	/// Asks for permission on first use; posts nothing when it is refused.
	var post: @Sendable (_ notification: HomerQuestionNotification) async -> Void
	var isAppActive: @Sendable () async -> Bool = { false }
}

extension HomerNotificationClient: DependencyKey {
	static let liveValue = HomerNotificationClient(
		post: { notification in
			let center = UNUserNotificationCenter.current()
			guard (try? await center.requestAuthorization(options: [.alert, .sound])) == true else {
				return
			}
			let content = UNMutableNotificationContent()
			content.title = notification.title
			content.subtitle = notification.subtitle
			content.body = notification.body
			content.sound = .default
			content.threadIdentifier = notification.instanceID
			content.userInfo = [HomerQuestionNotification.instanceKey: notification.instanceID]
			let request = UNNotificationRequest(identifier: notification.identifier, content: content, trigger: nil)
			try? await center.add(request)
		},
		isAppActive: {
			await MainActor.run { NSApp.isActive }
		}
	)
}

extension HomerNotificationClient: TestDependencyKey {
	static let testValue = HomerNotificationClient()
}
