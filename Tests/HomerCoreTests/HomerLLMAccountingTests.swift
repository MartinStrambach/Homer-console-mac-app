import Foundation
@testable import HomerCore
import Testing

@Suite("Homer LLM cost accounting")
struct HomerLLMAccountingTests {
	@Test("a harness command decodes how it was priced, and the run which source its cost came from")
	func decodesAccounting() throws {
		// The shape of `/api/v1/status/{id}`, trimmed: one Claude command priced by the session
		// endpoint, one plain command with no accounting.
		let json = """
			{
			  "id": 7, "status": "FINISHED", "agentName": "factory",
			  "costUsd": 0.42, "costSource": "mixed",
			  "executions": [
			    { "label": "plan", "resultCode": 0, "kind": "claude",
			      "llmAccounting": {
			        "sessionId": "abc-123", "costUsd": 0.4, "source": "session",
			        "fallbackReason": "incomplete: 3 of 5 calls ingested",
			        "usage": { "input": 1200, "output": 340, "cacheRead": 9000, "cacheWrite": 0, "reasoning": 12 }
			      } },
			    { "label": "build", "resultCode": 0, "kind": "cmd", "llmAccounting": null }
			  ]
			}
			"""
		let process = try JSONDecoder().decode(HomerProcess.self, from: Data(json.utf8))

		#expect(process.costSource == "mixed")
		let accounting = try #require(process.executions.first?.llmAccounting)
		#expect(accounting == HomerLLMAccounting(
			sessionId: "abc-123",
			costUsd: 0.4,
			source: "session",
			fallbackReason: "incomplete: 3 of 5 calls ingested",
			usage: .init(input: 1200, output: 340, cacheRead: 9000, reasoning: 12)
		))
		#expect(process.executions.last?.llmAccounting == nil)
	}

	@Test("a server that predates the accounting sends neither, and a sparse accounting decodes")
	func decodesOlderAndSparse() throws {
		let older = try JSONDecoder().decode(
			HomerProcess.self,
			from: Data(#"{ "id": 1, "status": "FINISHED", "agentName": "a", "executions": [{ "label": "x", "resultCode": 0 }] }"#.utf8)
		)
		#expect(older.costSource == nil)
		#expect(older.executions.first?.llmAccounting == nil)

		let sparse = try JSONDecoder().decode(HomerLLMAccounting.self, from: Data(#"{ "costUsd": 0.1 }"#.utf8))
		#expect(sparse == HomerLLMAccounting(costUsd: 0.1, source: "cli"))
	}

	@Test("the figure reads as charged, or as not reported when nothing priced it")
	func costText() {
		#expect(HomerLLMAccounting(costUsd: 0.1234, source: "cli").costText == "$0.1234")
		#expect(HomerLLMAccounting(costUsd: 0, source: "none").costText == "not reported")
	}

	@Test("a session reason is no fallback; any other source's is one")
	func fallbackText() {
		let session = HomerLLMAccounting(costUsd: 1, source: "session", fallbackReason: "incomplete: 3 of 5 calls ingested")
		#expect(session.fallbackText == "incomplete: 3 of 5 calls ingested")
		let cli = HomerLLMAccounting(costUsd: 1, source: "cli", fallbackReason: "session endpoint timed out")
		#expect(cli.fallbackText == "fallback: session endpoint timed out")
		#expect(HomerLLMAccounting(costUsd: 1, source: "cli").fallbackText == nil)
	}

	@Test("sources are worded as the console words them, an unknown one as itself")
	func sourceLabels() {
		#expect(HomerCostSource.label("session") == "proxy")
		#expect(HomerCostSource.label("cli") == "CLI estimate")
		#expect(HomerCostSource.label(nil) == "CLI estimate")
		#expect(HomerCostSource.label("mixed") == "mixed")
		#expect(HomerCostSource.label("none") == "not reported")
		#expect(HomerCostSource.label("ledger") == "ledger")
		#expect(HomerCostSource.explanation("ledger") == "Price source reported by the server.")
	}

	@Test("tokens list input and output, then only the counts that are not zero")
	func usageText() {
		let usage = HomerLLMAccounting.Usage(input: 1200, output: 340, cacheRead: 9000, reasoning: 12)
		#expect(usage.text == "in \(1200.formatted()) / out 340 / cache↑ \(9000.formatted()) / reasoning 12")
		#expect(HomerLLMAccounting.Usage(input: 5, output: 6).text == "in 5 / out 6")
	}
}
