import Foundation
import HomerCore

/// The Costs page's calls (`getCosts`, `getMonthlyCosts`, `getTotalCosts`, `getCostsByTag` in
/// `console/lib/api/client.ts`). All of them need the admin role; anyone else gets a 403.
extension HomerAPI {
	static func costSnapshot(baseURL: String) async throws -> HomerCostSnapshot {
		try await decode(HomerCostSnapshot.self, from: send("GET", "/api/v1/costs", baseURL: baseURL))
	}

	/// One UTC month (`YYYY-MM`); nil asks for the server's current month.
	static func monthlyCosts(baseURL: String, month: String?) async throws -> HomerMonthlyCosts {
		try await decode(
			HomerMonthlyCosts.self,
			from: send(
				"GET",
				"/api/v1/costs/monthly",
				baseURL: baseURL,
				queryItems: month.map { [URLQueryItem(name: "month", value: $0)] } ?? []
			)
		)
	}

	static func totalCosts(baseURL: String) async throws -> HomerTotalCosts {
		try await decode(HomerTotalCosts.self, from: send("GET", "/api/v1/costs/totals", baseURL: baseURL))
	}

	/// `encodeURIComponent`'s unreserved characters: a tag key is one path segment.
	private static let tagKeyAllowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_.!~*'()"))

	/// A key the server does not track (dropped by a config reload since the snapshot named it)
	/// is a 400, told in the server's words.
	static func costsByTag(baseURL: String, key: String) async throws -> HomerCostByTag {
		try await decode(
			HomerCostByTag.self,
			from: send(
				"GET",
				"/api/v1/costs/by-tag/" + (key.addingPercentEncoding(withAllowedCharacters: tagKeyAllowed) ?? key),
				baseURL: baseURL
			)
		)
	}
}
