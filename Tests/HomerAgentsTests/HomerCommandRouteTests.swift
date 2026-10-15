import Foundation
@testable import HomerAgents
import Testing

/// homer-slack's `router.test.ts`, case for case, and its `trigger`'s inputs.
@Suite("Homer command routing")
struct HomerCommandRouteTests {
	private let echo = HomerCommand(command: "", agent: "echo")
	private let askWeb = HomerCommand(command: "analyze", agent: "ask-web")

	@Test("mentions are removed and whitespace collapsed")
	func stripMention() {
		#expect(HomerCommandRoute.stripMention("<@U123> analyze this  thing") == "analyze this thing")
	}

	@Test("text naming no command goes to the default command, all of it the prompt")
	func defaultCommand() {
		#expect(HomerCommandRoute(text: "<@U1> hello world", commands: [echo]) == .command(echo, prompt: "hello world"))
	}

	@Test("a command word picks its command and leaves the prompt")
	func namedCommand() {
		#expect(HomerCommandRoute(text: "analyze the repo", commands: [askWeb, echo]) == .command(askWeb, prompt: "the repo"))
	}

	@Test("help lists the commands")
	func help() {
		#expect(HomerCommandRoute(text: "help", commands: [echo]) == .help)
	}

	@Test("no matching command and no default one is unknown")
	func unknown() {
		#expect(HomerCommandRoute(text: "frobnicate", commands: [askWeb]) == .unknown(command: "frobnicate"))
	}

	@Test("command words match in any case")
	func caseInsensitive() {
		#expect(HomerCommandRoute(text: "ANALYZE the repo", commands: [askWeb, echo]) == .command(askWeb, prompt: "the repo"))
	}

	@Test("nothing but a mention runs the default command with no prompt")
	func bareMention() {
		#expect(HomerCommandRoute(text: "<@U1>   ", commands: [echo]) == .command(echo, prompt: ""))
	}

	@Test("a command word wins over the default command")
	func commandOverDefault() {
		#expect(HomerCommandRoute(text: "analyze", commands: [askWeb, echo]) == .command(askWeb, prompt: ""))
	}

	@Test("a query command sends the static inputs, then the prompt")
	func queryRequest() {
		let command = HomerCommand(command: "check", agent: "factory-check", promptParam: "ticket_id", staticInputs: ["repo": "mobi"])

		let request = command.runRequest(prompt: "MOB-1234")

		#expect(request.queryItems == [URLQueryItem(name: "repo", value: "mobi"), URLQueryItem(name: "ticket_id", value: "MOB-1234")])
		#expect(request.bodyFields == nil)
	}

	@Test("a body command sends a JSON body, the prompt replacing a static input of its name")
	func bodyRequest() throws {
		let command = HomerCommand(command: "", agent: "ask-web", mode: .body, promptParam: "q", staticInputs: ["q": "default", "repo": "ask-web"])

		let request = command.runRequest(prompt: "hi")

		#expect(request.queryItems.isEmpty)
		let body = try #require(request.bodyJSON.flatMap { String(data: $0, encoding: .utf8) })
		#expect(body == #"{"q":"hi","repo":"ask-web"}"#)
	}

	@Test("an empty prompt is not sent, and a body command still sends a body")
	func emptyPrompt() {
		let command = HomerCommand(command: "status", agent: "factory-status", mode: .body, promptParam: "ticket_id")

		let request = command.runRequest(prompt: "")

		#expect(request.bodyJSON == Data("{}".utf8))
	}

	@Test("the server's JSON decodes, the connector's defaults filling what is missing")
	func decoding() throws {
		let json = #"""
		{"intro": "Hi", "commands": [
			{"command": "check", "agent": "factory-check", "description": "Check a ticket", "mode": "query", "promptParam": "ticket_id", "static": {}},
			{"agent": "factory"}
		]}
		"""#

		let list = try JSONDecoder().decode(HomerCommandList.self, from: Data(json.utf8))

		#expect(list == HomerCommandList(intro: "Hi", commands: [
			HomerCommand(command: "check", agent: "factory-check", description: "Check a ticket", promptParam: "ticket_id"),
			HomerCommand(command: "", agent: "factory"),
		]))
	}
}
