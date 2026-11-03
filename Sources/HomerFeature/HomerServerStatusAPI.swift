import Foundation
import HomerCore

/// The server's own state for an admin (`GET /api/v1/status`, `ServerStatusResponse`): when it
/// started and the newest run's id. Anyone else gets 403.
extension HomerAPI {
	static func serverStatus(baseURL: String) async throws -> HomerServerStatus {
		try await decode(HomerServerStatus.self, from: send("GET", "/api/v1/status", baseURL: baseURL))
	}
}

/// `ServerStatusResponse`. `startTime` is epoch seconds sent as a string (`ProcessManager`'s
/// `startTime`), `currentTime` an ISO 8601 instant (`Instant.now().toString()`); each is read in
/// either form.
public nonisolated struct HomerServerStatus: Equatable, Sendable, Decodable {
	/// When the server process started, in epoch seconds.
	public var startTime: Double
	/// The server's clock when it answered, in epoch seconds: the uptime is measured on it, so
	/// a skewed local clock does not skew it.
	public var currentTime: Double
	/// The newest run's id.
	public var lastProcessId: Int?

	public init(startTime: Double, currentTime: Double, lastProcessId: Int? = nil) {
		self.startTime = startTime
		self.currentTime = currentTime
		self.lastProcessId = lastProcessId
	}

	/// How long the server had been up when it answered.
	public var uptime: TimeInterval {
		max(0, currentTime - startTime)
	}

	/// "Up 3d 4h", "Up 4h 12m", "Up 12m" or "Up 40s": the account menu's line.
	static func uptimeText(_ seconds: TimeInterval) -> String {
		let seconds = max(0, Int(seconds))
		let minutes = seconds / 60
		let hours = minutes / 60
		let days = hours / 24
		if days > 0 {
			return "Up \(days)d \(hours % 24)h"
		}
		if hours > 0 {
			return "Up \(hours)h \(minutes % 60)m"
		}
		if minutes > 0 {
			return "Up \(minutes)m"
		}
		return "Up \(seconds)s"
	}

	private enum CodingKeys: String, CodingKey {
		case startTime, currentTime, lastProcessId
	}

	public init(from decoder: any Decoder) throws {
		let container = try decoder.container(keyedBy: CodingKeys.self)
		startTime = try Self.time(container, .startTime)
		currentTime = try Self.time(container, .currentTime)
		lastProcessId = try container.decodeIfPresent(Int.self, forKey: .lastProcessId)
	}

	private static func time(_ container: KeyedDecodingContainer<CodingKeys>, _ key: CodingKeys) throws -> Double {
		if let seconds = try? container.decode(Double.self, forKey: key) {
			return seconds
		}
		let text = try container.decode(String.self, forKey: key)
		guard let seconds = epochSeconds(text) else {
			throw DecodingError.dataCorruptedError(forKey: key, in: container, debugDescription: "Not a time: \(text)")
		}
		return seconds
	}

	/// "1730000000", or an instant as Java prints it: "2026-11-03T19:31:30Z", with 0, 3, 6 or 9
	/// fraction digits. The fraction is read apart, since `ISO8601DateFormatter` takes 3 at most.
	static func epochSeconds(_ text: String) -> Double? {
		if let seconds = Double(text) {
			return seconds
		}
		var whole = text
		var fraction = 0.0
		if let match = text.firstMatch(of: /\.(\d+)/) {
			fraction = Double("0.\(match.1)") ?? 0
			whole.removeSubrange(match.range)
		}
		guard let date = ISO8601DateFormatter().date(from: whole) else {
			return nil
		}
		return date.timeIntervalSince1970 + fraction
	}
}
