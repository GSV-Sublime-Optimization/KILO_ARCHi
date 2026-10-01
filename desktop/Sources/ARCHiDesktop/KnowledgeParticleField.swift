import Foundation
import CryptoKit

/// Presentation coordinates over existing records. Motion never edits knowledge.
/// Liminal v008 supplies the bounded local-spin idea; these are native 2D paths,
/// not Houdini simulation output or a scientific particle-physics model.
struct KnowledgeParticleField {
    struct Vector: Codable, Equatable, Sendable {
        var x: Double
        var y: Double
        static let zero = Self(x: 0, y: 0)
        static func + (a: Self, b: Self) -> Self { .init(x: a.x + b.x, y: a.y + b.y) }
        static func - (a: Self, b: Self) -> Self { .init(x: a.x - b.x, y: a.y - b.y) }
        static func * (a: Self, b: Double) -> Self { .init(x: a.x * b, y: a.y * b) }
        var length: Double { hypot(x, y) }
        func bounded(_ limit: Double) -> Self { self * min(1, limit / max(length, 1e-9)) }
    }
    struct Particle: Equatable {
        let nodeID: String
        let kind: CompanionGraphKind
        let orb: Vector
        let constellation: Vector
        let phase: Double
    }
    let particles: [Particle]
    let edges: [CompanionGraphEdge]
    let omittedCount: Int

    init(snapshot: CompanionGraphSnapshot) {
        // IDs, not array indices or particle proximity, own the correspondence.
        var seen = Set<String>()
        let sorted = snapshot.nodes.sorted { $0.id < $1.id }
            .filter { seen.insert($0.id).inserted }
        let nodes = Array(sorted.prefix(CompanionGraph.maximumNodes))
        let ids = Set(nodes.map(\.id))
        var edgeIDs = Set<String>()
        let validEdges = snapshot.edges.sorted { $0.id < $1.id }.filter {
            ids.contains($0.source) && ids.contains($0.target) && edgeIDs.insert($0.id).inserted
        }
        edges = Array(validEdges.prefix(CompanionGraph.maximumEdges))
        omittedCount = snapshot.truncatedCount + max(0, sorted.count - nodes.count)
            + max(0, validEdges.count - edges.count)
        let anchors: [Vector] = nodes.map { node in
            if node.kind == .companion { return .zero }
            let group = Double(CompanionGraphKind.allCases.firstIndex(of: node.kind) ?? 0)
            let angle = group * 2 * .pi / Double(CompanionGraphKind.allCases.count)
            let offset = Self.unit(node.id, salt: "position")
            return Vector(x: cos(angle) * 0.55, y: sin(angle) * 0.55) + offset * 0.24
        }
        var relaxed = anchors
        // A bounded deterministic layout: repel crowding, weakly attract recorded
        // neighbours, and retain a type anchor. Forces carry no epistemic meaning.
        let indices = Dictionary(uniqueKeysWithValues: nodes.enumerated().map { ($0.element.id, $0.offset) })
        for _ in 0..<36 {
            var force = nodes.indices.map { (anchors[$0] - relaxed[$0]) * 0.04 }
            for a in nodes.indices {
                for b in nodes.indices where b > a {
                    var delta = relaxed[a] - relaxed[b]
                    if delta.length < 1e-6 { delta = Self.unit(nodes[a].id + nodes[b].id, salt: "separate") * 0.01 }
                    let push = delta * (0.0014 / max(0.002, delta.length * delta.length))
                    force[a] = force[a] + push; force[b] = force[b] - push
                }
            }
            for edge in edges {
                guard let a = indices[edge.source], let b = indices[edge.target] else { continue }
                let pull = (relaxed[b] - relaxed[a]) * 0.009
                force[a] = force[a] + pull; force[b] = force[b] - pull
            }
            for index in nodes.indices {
                relaxed[index] = nodes[index].kind == .companion ? .zero
                    : (relaxed[index] + force[index].bounded(0.04)).bounded(0.86)
            }
        }
        particles = nodes.enumerated().map { index, node in
            let point = Self.unit(node.id, salt: "orb")
            let radius = 0.20 + 0.16 * Self.fraction(node.id, salt: "radius")
            return .init(nodeID: node.id, kind: node.kind,
                orb: node.kind == .companion ? .zero : point * radius,
                constellation: relaxed[index], phase: Self.fraction(node.id, salt: "phase") * 2 * .pi)
        }
    }

    /// Endpoint-exact bounded local curl; reduced motion removes the deviation.
    static func position(_ particle: Particle, spread: Double, reduceMotion: Bool) -> Vector {
        let t = spread.isFinite ? min(1, max(0, spread)) : 1
        let straight = particle.orb * (1 - t) + particle.constellation * t
        guard !reduceMotion, t > 0, t < 1 else { return straight }
        let envelope = pow(max(0, sin(.pi * t)), 1.5)
        let angle = 2 * Double.pi * 1.15 * t + particle.phase
        let deviation = Vector(x: cos(angle), y: sin(angle))
            * (min(0.065, 0.16 * (particle.constellation - particle.orb).length) * envelope)
        return straight + deviation
    }

    static func fraction(_ id: String, salt: String) -> Double {
        let digest = Array(SHA256.hash(data: Data((salt + ":" + id).utf8)))
        let value = digest.prefix(4).reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
        return Double(value) / Double(UInt32.max)
    }
    private static func unit(_ id: String, salt: String) -> Vector {
        let angle = fraction(id, salt: salt) * 2 * Double.pi
        return .init(x: cos(angle), y: sin(angle))
    }
}

/// Explicit local DCC export. No titles, source bodies, prompts or attribution.
/// The string node ID survives point reordering; ptnum is never knowledge identity.
struct KnowledgeParticleExport: Codable {
    struct Node: Codable {
        let nodeID: String
        let kind: String
        let orb: KnowledgeParticleField.Vector
        let constellation: KnowledgeParticleField.Vector
    }
    struct Edge: Codable { let id: String; let source: String; let target: String; let relationship: String }
    let schema: String
    let scope: String
    let omittedCount: Int
    let nodes: [Node]
    let edges: [Edge]
    init(field: KnowledgeParticleField) {
        schema = "archi-knowledge-particles/v1"
        scope = "Read-only presentation snapshot; IDs and recorded relationships only. No knowledge write-back."
        omittedCount = field.omittedCount
        nodes = field.particles.map { .init(nodeID: $0.nodeID, kind: $0.kind.rawValue, orb: $0.orb, constellation: $0.constellation) }
        edges = field.edges.map { .init(id: $0.id, source: $0.source, target: $0.target, relationship: $0.label) }
    }
    func data() throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }
}
