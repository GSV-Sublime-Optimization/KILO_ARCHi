import XCTest
@testable import ARCHiDesktop

final class LiminalKnowledgeBindingsTests: XCTestCase {
    private let digest = String(repeating: "a", count: 64)
    private let origin = String(repeating: "b", count: 64)
    private let session = UUID().uuidString
    private func graph(_ names: [String], status: String = "Retained") -> CompanionGraphSnapshot {
        .init(nodes: names.map { .init(id: $0, title: $0, subtitle: "v1", kind: .source,
            status: status, details: [.init(label: "Revision", value: "1")], target: .context) }, edges: [], truncatedCount: 0)
    }

    func testFilteringAndReorderingKeepActualBindings() throws {
        var map = try LiminalKnowledgeBindings(manifestSHA256: digest, lowDetailIDs: Array(0..<5000))
        let first = try map.project(graph(["a", "b", "c"]), sessionID: session, originDigest: origin)
        let reordered = try map.project(graph(["c", "b", "a"]), sessionID: session, originDigest: origin)
        XCTAssertEqual(first, reordered)
        XCTAssertEqual(first.filtered(to: ["b"]).bindings, first.bindings.filter { $0.nodeID == "b" })
        XCTAssertEqual(first.bindings.count, 3)
        XCTAssertEqual(Set(first.bindings.flatMap(\.particleIDs)).count, 96)
    }

    func testRetiredParticleDoesNotBecomeAnotherRecord() throws {
        var map = try LiminalKnowledgeBindings(manifestSHA256: digest, lowDetailIDs: Array(0..<5000))
        let first = try map.project(graph(["a", "b"]), sessionID: session, originDigest: origin)
        let later = try map.project(graph(["b", "c"]), sessionID: session, originDigest: origin)
        XCTAssertEqual(first.bindings.first { $0.nodeID == "b" }, later.bindings.first { $0.nodeID == "b" })
        XCTAssertTrue(Set(first.bindings.first { $0.nodeID == "a" }!.particleIDs)
            .isDisjoint(with: later.bindings.flatMap(\.particleIDs)))
    }

    func testCorrectionStaleSessionAndReplayCannotNavigate() throws {
        var map = try LiminalKnowledgeBindings(manifestSHA256: digest, lowDetailIDs: Array(0..<5000))
        let original = graph(["a"])
        let sidecar = try map.project(original, sessionID: session, originDigest: origin)
        let now = Date(timeIntervalSince1970: 1_000)
        let pick = LiminalKnowledgeSelection(schemaVersion: 1, sessionID: session, originDigest: origin,
            revision: 4, manifestSHA256: digest, graphDigest: sidecar.graphDigest, nodeID: "a",
            artParticleID: sidecar.bindings[0].anchorID, sequence: 1, updatedAtUnix: 1_000)
        XCTAssertEqual(pick.resolves(in: sidecar, graph: original, revisions: [4], after: 0, now: now)?.id, "a")
        XCTAssertNil(pick.resolves(in: sidecar, graph: graph(["a"], status: "Needs source review"), revisions: [4], after: 0, now: now))
        XCTAssertNil(pick.resolves(in: sidecar, graph: graph([]), revisions: [4], after: 0, now: now))
        XCTAssertNil(pick.resolves(in: sidecar, graph: original, revisions: [5], after: 0, now: now))
        XCTAssertNil(pick.resolves(in: sidecar, graph: original, revisions: [4], after: 1, now: now))
        XCTAssertNil(pick.resolves(in: sidecar, graph: original, revisions: [4], after: 0, now: now.addingTimeInterval(6)))
        let other = try map.project(original, sessionID: UUID().uuidString, originDigest: origin)
        XCTAssertNil(pick.resolves(in: other, graph: original, revisions: [4], after: 0, now: now))
    }

    func testInvalidIDsAndExhaustionFailWithoutInventingParticles() throws {
        XCTAssertThrowsError(try LiminalKnowledgeBindings(manifestSHA256: "v002", lowDetailIDs: [1]))
        XCTAssertThrowsError(try LiminalKnowledgeBindings(manifestSHA256: digest, lowDetailIDs: [1, 1]))
        var map = try LiminalKnowledgeBindings(manifestSHA256: digest, lowDetailIDs: Array(0..<32))
        XCTAssertThrowsError(try map.project(graph(["a", "b"]), sessionID: session, originDigest: origin))
    }
}
