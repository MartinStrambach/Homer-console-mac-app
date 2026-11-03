import Foundation
@testable import HomerRunners
import Testing

@Suite("Homer runner models")
struct HomerRunnerModelsTests {
	/// The shape of the server's `RunnersStatusResponse`: one of each kind, with a field the app
	/// does not read.
	private let runnersJSON = """
		{
		  "runners": [
		    { "alias": "local", "kind": "local", "tags": [], "concurrency": null, "inUse": 1, "instances": null },
		    { "alias": "build-box", "kind": "ssh", "tags": ["linux", "xcode"], "concurrency": 4, "inUse": 4 },
		    { "alias": "k8s", "kind": "kubernetes", "tags": ["gpu"], "concurrency": 8, "inUse": 2 },
		    {
		      "alias": "laptops", "kind": "external", "tags": [], "concurrency": null, "inUse": 3,
		      "instances": [
		        {
		          "instanceId": "a1", "name": "mbp-martin", "tags": ["mac"], "concurrency": 2,
		          "activeSessions": 2, "lastSeenAt": 1783420800, "registeredAt": 1783400000,
		          "draining": false
		        },
		        {
		          "instanceId": "b2", "name": "mini", "tags": ["mac"], "concurrency": 4,
		          "activeSessions": 1, "lastSeenAt": 1783420790, "registeredAt": 1783410000,
		          "draining": true
		        }
		      ]
		    }
		  ],
		  "somethingNewer": true
		}
		"""

	@Test("the runners decode, unknown fields ignored, and each instance knows its domain")
	func decodesRunners() throws {
		let runners = try JSONDecoder().decode(HomerRunners.self, from: Data(runnersJSON.utf8))

		#expect(runners.runners.map(\.alias) == ["local", "build-box", "k8s", "laptops"])
		#expect(runners.runners[1].tags == ["linux", "xcode"])
		#expect(runners.runners[1].concurrency == 4)
		#expect(runners.runners[0].concurrency == nil)
		#expect(runners.hasExternalRunners)
		#expect(runners.externalInstances.map(\.name) == ["mbp-martin", "mini"])
		#expect(runners.externalInstances.map(\.domain) == ["laptops", "laptops"])
		#expect(runners.externalInstances[1].draining)
		#expect(runners.externalInstances[0].lastSeenAt == 1_783_420_800)
	}

	@Test("capacity reads like the console's: bounded, unbounded, external")
	func capacityText() throws {
		let runners = try JSONDecoder().decode(HomerRunners.self, from: Data(runnersJSON.utf8)).runners

		#expect(runners.map(\.capacityText) == ["1 / unbounded", "4 / 4", "2 / 8", "3 active"])
		#expect(runners.map(\.load) == [nil, 1, 0.25, nil])
		#expect(runners[3].instances.map(\.capacityText) == ["2 / 2", "1 / 4"])
	}

	@Test("a runner without tags or instances decodes; one without its alias does not")
	func lenientDecoding() throws {
		let runner = try JSONDecoder().decode(HomerRunner.self, from: Data(#"{ "alias": "x", "kind": "local", "inUse": 0 }"#.utf8))
		#expect(runner.tags.isEmpty)
		#expect(runner.instances.isEmpty)

		#expect(throws: (any Error).self) {
			try JSONDecoder().decode(HomerRunners.self, from: Data(#"{ "processes": [] }"#.utf8))
		}
		#expect(throws: (any Error).self) {
			try JSONDecoder().decode(HomerRunner.self, from: Data(#"{ "kind": "local", "inUse": 0 }"#.utf8))
		}
	}

	@Test("the claim queue decodes, each group described by what it waits for")
	func decodesQueue() throws {
		let json = """
			{
			  "pending": 3,
			  "oldestAgeSec": 125,
			  "byFilter": [
			    { "filter": { "alias": "k8s", "tags": null }, "pending": 1, "oldestAgeSec": 125 },
			    { "filter": { "alias": null, "tags": ["gpu", "linux"] }, "pending": 2, "oldestAgeSec": 7 }
			  ]
			}
			"""
		let queue = try JSONDecoder().decode(HomerRunnerQueue.self, from: Data(json.utf8))

		#expect(queue.pending == 3)
		#expect(queue.oldestAgeSec == 125)
		#expect(queue.byFilter.map(\.filter.description) == ["runner k8s", "tags gpu, linux"])
		#expect(queue.byFilter.map(\.pending) == [1, 2])
		#expect(HomerRunnerFormat.age(seconds: 125) == "2m 5s")
		#expect(HomerRunnerFormat.age(seconds: 7) == "7s")
	}

	@Test("an empty claim queue decodes")
	func decodesEmptyQueue() throws {
		let queue = try JSONDecoder().decode(HomerRunnerQueue.self, from: Data(#"{ "pending": 0, "byFilter": [] }"#.utf8))

		#expect(queue == HomerRunnerQueue(pending: 0))
	}
}
