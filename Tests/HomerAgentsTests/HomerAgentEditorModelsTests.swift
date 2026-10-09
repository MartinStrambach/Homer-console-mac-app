import Dependencies
import Foundation
@testable import HomerAgents
@testable import HomerCore
import Testing

@Suite("Homer agent editor models")
struct HomerAgentEditorModelsTests {
	@Test("a file's path is encoded segment by segment, the agent's name as a whole")
	func filePaths() {
		#expect(HomerAPI.agentFilesPath(agentName: "team/a b") == "/api/v1/agents/team%2Fa%20b/files")
		#expect(
			HomerAPI.agentFilePath(agentName: "factory", path: "prompts/review #1.md")
				== "/api/v1/agents/factory/files/prompts/review%20%231.md"
		)
	}

	@Test("the file list decodes, and sorts directories first, then by path")
	func fileList() throws {
		let json = """
		{"entries":[
			{"path":"run.sh","size":12,"mtime":1760000000,"isDirectory":false},
			{"path":"agent.yaml","size":40,"mtime":1760000000,"isDirectory":false},
			{"path":"prompts","size":0,"mtime":1760000000,"isDirectory":true},
			{"path":"README.md"}
		]}
		"""
		let files = try JSONDecoder().decode(HomerAgentFileList.self, from: Data(json.utf8)).entries
		#expect(HomerAgentFile.sorted(files).map(\.path) == ["prompts", "agent.yaml", "README.md", "run.sh"])
		#expect(files[1].isDefinition)
		#expect(!files[0].isDefinition)
		#expect(files[3] == HomerAgentFile(path: "README.md"))
	}

	@Test("the debug request's maps take trimmed keys, skip empty ones, and the last row of a key wins")
	func debugRequest() throws {
		let rows = [
			HomerKeyValue(id: UUID(0), key: " ticket ", value: "A"),
			HomerKeyValue(id: UUID(1), key: "", value: "dropped"),
			HomerKeyValue(id: UUID(2), key: "ticket", value: "B"),
		]
		let request = HomerAgentDebugRequest(
			commandIndex: 1,
			env: [HomerKeyValue(id: UUID(3), key: "DEBUG", value: "1")],
			params: rows
		)
		#expect(request.queryParams == ["ticket": "B"])

		let encoder = JSONEncoder()
		encoder.outputFormatting = .sortedKeys
		let json = try #require(String(data: encoder.encode(request), encoding: .utf8))
		#expect(json == #"{"commandIndex":1,"env":{"DEBUG":"1"},"queryParams":{"ticket":"B"}}"#)
	}

	@Test("the editor's language follows the file's extension, as Monaco's does")
	func languages() {
		#expect(HomerAgentFileLanguage(path: "agent.YAML") == .yaml)
		#expect(HomerAgentFileLanguage(path: "agent.yml") == .yaml)
		#expect(HomerAgentFileLanguage(path: "agent.json") == .json)
		#expect(HomerAgentFileLanguage(path: "scripts/run.bash") == .shell)
		#expect(HomerAgentFileLanguage(path: "graph.py") == .python)
		#expect(HomerAgentFileLanguage(path: "tool.mjs") == .javascript)
		#expect(HomerAgentFileLanguage(path: "prompt.md") == .markdown)
		#expect(HomerAgentFileLanguage(path: "Makefile") == .plaintext)
	}

	@Test("YAML: keys, quoted strings, literals and comments; an apostrophe in plain text is no string")
	func yamlColors() {
		let yaml = """
		name: factory # the agent
		cron:
		  enabled: true
		  retries: 3
		description: it's Bob's "agent"
		commands:
		  - "echo hi"
		"""
		func text(_ kind: HomerSyntaxHighlighter.Kind) -> [String] {
			HomerSyntaxHighlighter.tokens(in: yaml, language: .yaml)
				.filter { $0.kind == kind }
				.map { (yaml as NSString).substring(with: $0.range) }
		}
		#expect(text(.key) == ["name", "cron", "enabled", "retries", "description", "commands"])
		#expect(text(.comment) == ["# the agent"])
		#expect(text(.literal) == ["true", "3"])
		#expect(text(.string) == ["\"agent\"", "\"echo hi\""])
	}

	@Test("JSON: keys over strings, numbers and literals outside strings")
	func jsonColors() {
		let json = #"{"name": "agent 2", "scriptCount": 2, "writable": false}"#
		let tokens = HomerSyntaxHighlighter.tokens(in: json, language: .json)
		func text(_ kind: HomerSyntaxHighlighter.Kind) -> [String] {
			tokens.filter { $0.kind == kind }.map { (json as NSString).substring(with: $0.range) }
		}
		#expect(text(.key) == [#""name""#, #""scriptCount""#, #""writable""#])
		#expect(text(.literal) == ["2", "false"])
		#expect(text(.string).contains(#""agent 2""#))
	}

	@Test("a schema refusal reads as the server's message and its reasons")
	func invalidDescription() {
		let error = HomerAPIError.invalid(message: "Agent definition invalid", errors: ["$.name: required"])
		#expect(error.localizedDescription == "Agent definition invalid\n$.name: required")
	}
}
