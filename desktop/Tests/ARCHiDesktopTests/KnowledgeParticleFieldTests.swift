import XCTest
@testable import ARCHiDesktop

final class KnowledgeParticleFieldTests: XCTestCase {
    private func node(_ id: String, _ kind: CompanionGraphKind = .knowledge) -> CompanionGraphNode {
        .init(id: id, title: "Private title", subtitle: "Private subtitle", kind: kind,
            status: "Private status", details: [.init(label: "Your note", value: "Private body")], target: .memory)
    }

    func testStableIdentityAndLayoutIgnoreInputOrderAndRejectPhantomEdges() {
        let nodes = [node("root", .companion), node("b"), node("a", .source)]
        let edges = [CompanionGraphEdge(id: "ab", source: "a", target: "b", label: "source passage"),
                     .init(id: "bad", source: "absent", target: "b", label: "never drawn")]
        let first = KnowledgeParticleField(snapshot: .init(nodes: nodes, edges: edges, truncatedCount: 0))
        let second = KnowledgeParticleField(snapshot: .init(nodes: nodes.reversed(), edges: edges.reversed(), truncatedCount: 0))
        XCTAssertEqual(first.particles, second.particles)
        XCTAssertEqual(Set(first.particles.map(\.nodeID)), Set(nodes.map(\.id)))
        XCTAssertEqual(first.edges.map(\.id), ["ab"])
    }

    func testEndpointExactAndBoundedCurlForDenseSnapshot() {
        let field = KnowledgeParticleField(snapshot: .init(nodes: (0..<220).map { node("node-\($0)") }, edges: [], truncatedCount: 0))
        for p in field.particles {
            XCTAssertEqual(KnowledgeParticleField.position(p, spread: 0, reduceMotion: false), p.orb)
            XCTAssertEqual(KnowledgeParticleField.position(p, spread: 1, reduceMotion: false), p.constellation)
            for t in [0.01, 0.25, 0.5, 0.75, 0.99] {
                let straight = p.orb * (1-t) + p.constellation * t
                let limit = min(0.065, 0.16 * (p.constellation - p.orb).length)
                let actual = KnowledgeParticleField.position(p, spread: t, reduceMotion: false)
                XCTAssertLessThanOrEqual((actual - straight).length, limit + 1e-12)
                XCTAssertLessThanOrEqual(actual.length, 0.93)
                XCTAssertEqual(KnowledgeParticleField.position(p, spread: t, reduceMotion: true), straight)
            }
            XCTAssertEqual(KnowledgeParticleField.position(p, spread: .nan, reduceMotion: false), p.constellation)
        }
    }

    func testCapsAndExportPreserveIDsWithoutPrivateContents() throws {
        let nodes = (0..<230).map { node("node-\($0)") }
        let field = KnowledgeParticleField(snapshot: .init(nodes: nodes, edges: [], truncatedCount: 7))
        XCTAssertEqual(field.particles.count, 220)
        XCTAssertEqual(field.omittedCount, 17)
        let data = try KnowledgeParticleExport(field: field).data()
        let decoded = try JSONDecoder().decode(KnowledgeParticleExport.self, from: data)
        XCTAssertEqual(decoded.nodes.map(\.nodeID), field.particles.map(\.nodeID))
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("Private"))
        XCTAssertEqual(decoded.schema, "archi-knowledge-particles/v1")
    }

    func testExportFixtureForHoudiniAdapter() throws {
        let graph = CompanionGraphSnapshot(nodes: [node("root", .companion), node("source", .source), node("concept")],
            edges: [.init(id: "link-1", source: "concept", target: "source", label: "source passage")], truncatedCount: 0)
        let data = try KnowledgeParticleExport(field: KnowledgeParticleField(snapshot: graph)).data()
        let path = ProcessInfo.processInfo.environment["ARCHI_PARTICLE_EXPORT_FIXTURE"]
        if let path { try data.write(to: URL(fileURLWithPath: path)) }
        XCTAssertEqual(try JSONDecoder().decode(KnowledgeParticleExport.self, from: data).nodes.count, 3)
    }
}
