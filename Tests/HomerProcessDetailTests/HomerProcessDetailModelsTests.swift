import Foundation
@testable import HomerCore
@testable import HomerProcessDetail
@testable import HomerWorkflowGraph
import Testing

@Suite("Homer process page models")
struct HomerProcessDetailModelsTests {
	@Test("a process's page fields decode: execution files, runner times, Langfuse trace")
	func decodesProcessDetail() throws {
		let json = """
			{
			  "id": 7, "status": "FAILED", "agentName": "factory",
			  "history": [{ "timestamp": 1700000000, "status": "CREATED" }],
			  "executions": [
			    { "label": "build", "start": 1700000010, "end": 1700000075, "resultCode": 2,
			      "stdOut": "/tmp/homer/workspace-7/artifacts/cmd_0.out",
			      "stdErr": "/tmp/homer/workspace-7/artifacts/cmd_0.err", "errMsg": "exit 2" }
			  ],
			  "currentCommand": null, "currentCommandStart": 1700000080, "purgeAt": null,
			  "runner": {
			    "alias": "k8s-dev", "podName": "homer-7", "podPhase": "FAILED", "createdAt": 1700000001,
			    "startupFailure": { "reason": "ImagePullBackOff", "message": "no such image", "events": ["pulled"] }
			  },
			  "langfuseTraceUrl": "https://langfuse.example.com/trace/7"
			}
			"""

		let process = try JSONDecoder().decode(HomerProcess.self, from: Data(json.utf8))

		let execution = try #require(process.executions.first)
		#expect(execution.start == 1_700_000_010)
		#expect(execution.end == 1_700_000_075)
		#expect(execution.stdOut == "/tmp/homer/workspace-7/artifacts/cmd_0.out")
		#expect(execution.errMsg == "exit 2")
		#expect(process.currentCommandStart == 1_700_000_080)
		#expect(process.runner?.createdAt == 1_700_000_001)
		#expect(process.runner?.startupFailure == .init(reason: "ImagePullBackOff", message: "no such image", events: ["pulled"]))
		#expect(process.langfuseTraceUrl == "https://langfuse.example.com/trace/7")
		#expect(process.isResumeEligible)
	}

	@Test("a run's messages decode, an unknown status included")
	func decodesRunMessages() throws {
		let json = """
			{ "messages": [
			  { "id": "a1", "processId": 7, "text": "use staging", "status": "DELIVERED",
			    "sender": "session:admin", "createdAt": 1700000000, "deliveredAt": 1700000030 },
			  { "id": "a2", "processId": 7, "text": "and hurry", "status": "RECALLED", "createdAt": 1700000040 }
			] }
			"""
		let messages = try JSONDecoder().decode(HomerRunMessageList.self, from: Data(json.utf8)).messages

		#expect(messages.map(\.status) == [.delivered, .unknown])
		#expect(messages.first?.sender == "session:admin")
		#expect(messages.first?.deliveredAt == 1_700_000_030)
		#expect(messages.last?.sender == nil)
	}

	@Test("artifact paths: an execution's absolute path is cut to its name, a listed one kept")
	func artifactPaths() {
		#expect(HomerArtifactPath.apiPath("/tmp/homer/workspace-7/artifacts/cmd_0.out") == "cmd_0.out")
		#expect(HomerArtifactPath.apiPath("reports/summary.json") == "reports/summary.json")
		#expect(HomerArtifactPath.fileName("reports/summary.json") == "summary.json")
		#expect(HomerArtifactPath.liveOutput(executionIndex: 3, stream: .stderr) == "cmd_3.err")
	}

	@Test("workflow nodes come in the order the Mermaid source declares them")
	func workflowNodeOrder() throws {
		let json = #"""
			{
			  "label": "workflow", "module": "flow", "threadId": "t-1",
			  "mermaid": "graph TD;\n\t__start__([<p>__start__</p>]):::first\n\tplan(plan)\n\tfan\\20out(fan out)\n\treview(review)\n\t__start__ --> plan;\n\tplan --> fan\\20out;\n",
			  "nodes": { "review": "pending", "fan out": "parked", "plan": "done" },
			  "subs": { "fan out": [
			    { "interruptId": "i-1", "processId": 8, "agentName": "worker", "status": "FINISHED",
			      "commands": [{ "label": "run", "state": "ok" }] },
			    { "interruptId": "i-2", "processId": 9, "agentName": "worker", "status": "FINISHED" }
			  ] }
			}
			"""#

		let status = try JSONDecoder().decode(HomerLangGraphStatus.self, from: Data(json.utf8))

		#expect(status.nodes.map(\.name) == ["plan", "fan out", "review"])
		#expect(status.subsFinished(node: "fan out"))
		#expect(!status.subsFinished(node: "plan"))
		#expect(status.allSubs.map(\.sub.interruptId) == ["i-1", "i-2"])
	}

	@Test("workflow nodes come in the topology's order, ahead of the Mermaid source's; taken edges by node")
	func workflowNodeOrderFromTopology() throws {
		let json = #"""
			{
			  "label": "workflow", "module": "flow", "threadId": "t-1",
			  "topology": {
			    "nodes": [{ "id": "__start__" }, { "id": "review" }, { "id": "fan out" }, { "id": "plan" }, { "id": "__end__" }],
			    "edges": [
			      { "source": "__start__", "target": "review", "label": null, "conditional": false },
			      { "source": "review", "target": "fan out", "conditional": true },
			      { "source": "review", "target": "plan", "label": "retry", "conditional": true }
			    ]
			  },
			  "mermaid": "graph TD;\n\tplan(plan)\n\tfan\\20out(fan out)\n\treview(review)\n",
			  "nodes": { "plan": "pending", "fan out": "parked", "review": "done", "extra": "pending" },
			  "traversed": [
			    { "source": "__start__", "target": "review" },
			    { "source": "review", "target": "fan out" },
			    { "source": "review", "target": "plan" }
			  ]
			}
			"""#

		let status = try JSONDecoder().decode(HomerLangGraphStatus.self, from: Data(json.utf8))

		#expect(status.nodes.map(\.name) == ["review", "fan out", "plan", "extra"])
		#expect(status.takenTargets(from: "review") == ["fan out", "plan"])
		#expect(status.takenTargets(from: "plan").isEmpty)
		#expect(status.hasGraph)
	}

	@Test("without a topology or Mermaid source the nodes are listed by name, with no graph")
	func workflowNodesWithoutGraph() {
		let status = HomerLangGraphStatus(label: "workflow", threadId: "t", nodeStates: ["b": "done", "a": "pending"])

		#expect(status.nodes.map(\.name) == ["a", "b"])
		#expect(!status.hasGraph)
		#expect(status.takenTargets(from: "a").isEmpty)
	}

	@Test("Mermaid node ids escape like langchain's `_to_safe_id`")
	func mermaidSafeID() {
		#expect(HomerLangGraphStatus.mermaidSafeID("plan_step-2") == "plan_step-2")
		#expect(HomerLangGraphStatus.mermaidSafeID("fan out.v2") == "fan\\20out\\2ev2")
	}

	@Test("a server-sent event is its fields up to the blank line; comments are skipped")
	func serverSentEvents() {
		var parser = HomerServerSentEventParser()
		var events: [HomerServerSentEvent] = []
		for line in [": ping", "event: log.chunk", "id: 42", #"data: {"content":"hi"}"#, "", "", "event: log.end", "data: {}", ""] {
			if let event = parser.consume(line: line) {
				events.append(event)
			}
		}

		#expect(events == [
			HomerServerSentEvent(name: "log.chunk", id: "42", data: #"{"content":"hi"}"#),
			HomerServerSentEvent(name: "log.end", id: nil, data: "{}"),
		])
	}

	@Test("a download takes the next free name, as a browser's does")
	func downloadName() {
		let folder = URL(filePath: "/Users/me/Downloads")
		let taken: Set<String> = ["report.json", "report 2.json", "notes"]

		let report = HomerDownloads.availableURL(in: folder, fileName: "report.json") { taken.contains($0.lastPathComponent) }
		let notes = HomerDownloads.availableURL(in: folder, fileName: "notes") { taken.contains($0.lastPathComponent) }
		let fresh = HomerDownloads.availableURL(in: folder, fileName: "cmd_0.out") { taken.contains($0.lastPathComponent) }

		#expect(report.lastPathComponent == "report 3.json")
		#expect(notes.lastPathComponent == "notes 2")
		#expect(fresh.lastPathComponent == "cmd_0.out")
	}

	@Test("a command's duration reads like the console's")
	func duration() {
		#expect(HomerFormat.duration(from: 100, to: 105) == "5s")
		#expect(HomerFormat.duration(from: 100, to: 225) == "2m 5s")
		#expect(HomerFormat.duration(from: 0, to: 3725) == "1h 2m 5s")
	}
}

@Suite("Retained artifact globs")
struct HomerArtifactGlobTests {
	private func matches(_ glob: String, _ path: String) -> Bool {
		HomerArtifactGlob(glob)?.matches(path) == true
	}

	@Test("star and question mark stay within a segment; a double star crosses them")
	func wildcards() {
		#expect(matches("*.json", "result.json"))
		#expect(!matches("*.json", "reports/result.json"))
		#expect(matches("**.json", "reports/result.json"))
		#expect(matches("reports/**", "reports/a/b.txt"))
		#expect(!matches("reports/**", "logs/a.txt"))
		#expect(matches("report?.txt", "report1.txt"))
		#expect(!matches("report?.txt", "report/.txt"))
		#expect(matches("a.b", "a.b"))
		#expect(!matches("a.b", "axb"))
	}

	@Test("groups and classes match as Java's glob does; a malformed glob matches nothing")
	func groupsAndClasses() {
		#expect(matches("*.{json,md}", "notes.md"))
		#expect(!matches("*.{json,md}", "notes.txt"))
		#expect(matches("run[0-9].log", "run7.log"))
		#expect(!matches("run[!0-9].log", "run7.log"))
		#expect(matches("run[!0-9].log", "runx.log"))
		#expect(HomerArtifactGlob("*.{json") == nil)
		#expect(HomerArtifactGlob("run[0-9.log") == nil)
		#expect(HomerArtifactGlob("{a,{b}}") == nil)
	}
}

@Suite("LLM harness conversation")
struct HomerLLMConversationTests {
	private func event(_ json: String) throws -> HomerLLMEvent {
		try #require(HomerLLMEvent(frame: #"{"processId":7,"cmdIndex":1,"attemptIndex":0,"event":"# + json + "}"))
	}

	@Test("every kind of event decodes from its frame; an unknown kind is ignored")
	func decodesEvents() throws {
		#expect(try event(#"{"type":"session_start","sessionId":"s1","model":"gpt-5.5","tools":["shell"]}"#) == .sessionStart(model: "gpt-5.5"))
		#expect(try event(#"{"type":"assistant_message","messageId":"m1","model":null,"text":"Looking.","subagent":false}"#)
			== .assistantMessage(messageID: "m1", text: "Looking."))
		#expect(try event(#"{"type":"tool_call","id":"t1","name":"shell","input":{"command":"ls"},"messageId":"m1"}"#)
			== .toolCall(.init(id: "t1", name: "shell", input: "{\n  \"command\" : \"ls\"\n}", inputPreview: #"{"command":"ls"}"#, messageID: "m1")))
		#expect(try event(#"{"type":"tool_result","id":"t1","output":"a.txt","isError":true}"#) == .toolResult(id: "t1", output: "a.txt", isError: true))
		#expect(try event(#"{"type":"transient_error","message":"overloaded"}"#) == .other)
		#expect(try event(#"{"type":"something_new"}"#) == .other)
		#expect(HomerLLMEvent(frame: "not json") == nil)

		let turnEnd = try event(#"""
			{"type":"turn_end","status":{"type":"stopped","reason":"max turns"},
			 "usage":{"input":20,"output":9,"cacheRead":100,"cacheWrite":0,"reasoning":7},
			 "costUsd":null,"model":"gpt-5.5","durationMs":4200,"durationApiMs":null,"numTurns":2,"resultText":"Done."}
			"""#)
		#expect(turnEnd == .turnEnd(.init(
			status: .stopped(reason: "max turns"),
			usage: .init(input: 20, output: 9, cacheRead: 100, reasoning: 7),
			costUsd: nil,
			model: "gpt-5.5",
			durationMs: 4200,
			turns: 2
		)))
	}

	@Test("messages and tool calls in order, each call with its result; turns by message id")
	func conversation() {
		let conversation = HomerLLMConversation([
			.sessionStart(model: nil),
			.sessionStart(model: "claude-opus-5-5"),
			.assistantMessage(messageID: "m1", text: "Looking."),
			.toolCall(.init(id: "t1", name: "Bash", input: "{}", inputPreview: "{}", messageID: "m1")),
			.toolResult(id: "t1", output: "a.txt", isError: false),
			// Thinking only: no row, but a turn.
			.assistantMessage(messageID: "m2", text: "  "),
			.assistantMessage(messageID: "m3", text: "Done."),
			.turnEnd(.init(status: .success, model: "claude-opus-5-5-20261101")),
			.turnEnd(.init(status: .failed(reason: "late"))),
		])

		#expect(conversation.items.map(\.id) == ["message-0", "tool-t1", "message-2"])
		guard case let .tool(_, result) = conversation.items[1] else {
			Issue.record("expected the tool call")
			return
		}
		#expect(result?.output == "a.txt")
		#expect(conversation.turns == 3)
		#expect(conversation.lastMessageIndex == 2)
		#expect(conversation.inflightToolID == nil)
		// The first turn_end is the outcome, and its model wins over the session's.
		#expect(conversation.outcome?.status == .success)
		#expect(conversation.model == "claude-opus-5-5-20261101")
	}

	@Test("a call without a result is in flight; a result before its call still lands on it")
	func inflightAndEarlyResult() {
		var conversation = HomerLLMConversation([
			.toolResult(id: "t2", output: "early", isError: false),
			.toolCall(.init(id: "t1", name: "Read", input: "{}", inputPreview: "{}")),
		])
		#expect(conversation.inflightToolID == "t1")
		#expect(conversation.outcome == nil)

		conversation.apply(.toolCall(.init(id: "t2", name: "Grep", input: "{}", inputPreview: "{}")))
		guard case let .tool(_, result) = conversation.items[1] else {
			Issue.record("expected the tool call")
			return
		}
		#expect(result?.output == "early")
		#expect(conversation.inflightToolID == "t1")
	}

	@Test("a cursor follows its attempt; a replayed event and a new attempt are told apart")
	func cursorPlacement() throws {
		let last = try #require(HomerLLMCursor("1:0:1702:1"))
		#expect(try #require(HomerLLMCursor("1:0:1702:2")).placement(after: last) == .next)
		#expect(try #require(HomerLLMCursor("1:0:2000:0")).placement(after: last) == .next)
		#expect(try #require(HomerLLMCursor("1:0:1702:1")).placement(after: last) == .replay)
		#expect(try #require(HomerLLMCursor("1:0:10:0")).placement(after: last) == .replay)
		#expect(try #require(HomerLLMCursor("1:1:0:0")).placement(after: last) == .newAttempt)
		#expect(try #require(HomerLLMCursor("1:0:0:0")).placement(after: nil) == .next)
		#expect(HomerLLMCursor("1702") == nil)
		#expect(HomerLLMCursor(nil) == nil)
	}

	@Test("a command's kind names its harness")
	func harness() {
		#expect(HomerLLMHarness(kind: "codex") == .codex)
		#expect(HomerLLMHarness(kind: "opencode")?.title == "opencode")
		#expect(HomerLLMHarness(kind: "script") == nil)
		#expect(HomerLLMHarness(kind: "") == nil)
		#expect(HomerLLMHarness(kind: nil) == nil)
	}
}
