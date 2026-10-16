import ComposableArchitecture
import Foundation
import Synchronization

/// How to reach the conversation proxy of one Homer instance: its URL and the client token it
/// knows this user by. The token is the proxy's own, nothing to do with the Homer session, so
/// signing out of Homer leaves it in place.
public nonisolated struct HomerProxySettings: Codable, Equatable, Sendable {
	public var url: String
	public var token: String

	public init(url: String, token: String) {
		self.url = url
		self.token = token
	}
}

/// The proxy settings of every instance, keyed by the instance's base URL, persisted to
/// `homerProxies.json` in Application Support beside the sessions, readable by the user alone
/// (`0600`) — the token is a secret, which rules out `@Shared(.fileStorage)`: it cannot set
/// the file's permissions.
nonisolated final class HomerProxySettingsStore: Sendable {
	static let shared = HomerProxySettingsStore(fileURL: applicationSupportURL(name: "homerProxies.json"))

	private let fileURL: URL?
	private let settings: Mutex<[String: HomerProxySettings]>

	/// `fileURL` nil keeps the settings in memory only.
	init(fileURL: URL?) {
		self.fileURL = fileURL
		let stored = fileURL
			.flatMap { try? Data(contentsOf: $0) }
			.flatMap { try? JSONDecoder().decode([String: HomerProxySettings].self, from: $0) }
		self.settings = Mutex(stored ?? [:])
	}

	func settings(for baseURL: String) -> HomerProxySettings? {
		settings.withLock { $0[baseURL] }
	}

	func save(_ value: HomerProxySettings, for baseURL: String) {
		settings.withLock { settings in
			settings[baseURL] = value
			save(settings)
		}
	}

	func remove(for baseURL: String) {
		settings.withLock { settings in
			guard settings.removeValue(forKey: baseURL) != nil else {
				return
			}
			save(settings)
		}
	}

	/// Called with the lock held, so writes land in the order the changes were made.
	private func save(_ settings: [String: HomerProxySettings]) {
		guard let fileURL, let data = try? JSONEncoder().encode(settings) else {
			return
		}
		let fileManager = FileManager.default
		try? fileManager.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
		guard (try? data.write(to: fileURL, options: .atomic)) != nil else {
			return
		}
		try? fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
	}
}

/// The proxy settings as a dependency, so a reducer reads and writes them without touching the
/// file, and a test gives it whatever it likes.
@DependencyClient
public struct HomerProxySettingsClient: Sendable {
	/// The instance's proxy, if one was connected.
	public var load: @Sendable (_ baseURL: String) -> HomerProxySettings?
	public var save: @Sendable (_ baseURL: String, _ settings: HomerProxySettings) -> Void
	public var remove: @Sendable (_ baseURL: String) -> Void
}

extension HomerProxySettingsClient: DependencyKey {
	public static let liveValue = HomerProxySettingsClient(
		load: { HomerProxySettingsStore.shared.settings(for: $0) },
		save: { HomerProxySettingsStore.shared.save($1, for: $0) },
		remove: { HomerProxySettingsStore.shared.remove(for: $0) }
	)
}

extension HomerProxySettingsClient: TestDependencyKey {
	public static let testValue = HomerProxySettingsClient()
}
