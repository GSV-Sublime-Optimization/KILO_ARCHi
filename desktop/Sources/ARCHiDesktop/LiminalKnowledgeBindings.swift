import Foundation
import CryptoKit

/// A disposable presentation map, never a second knowledge store. Reservations
/// survive filtering and removal for the lifetime of this asset/session so an
/// old particle cannot silently become a different record.
struct LiminalKnowledgeBindings {
    struct Binding: Codable, Equatable {
        let nodeID: String
        let anchorID: UInt32
        let particleIDs: [UInt32]
    }
    struct Sidecar: Codable, Equatable {
        let schemaVersion: Int
        let sessionID: String
        let originDigest: String
        let manifestSHA256: String
        let graphDigest: String
        let bindings: [Binding]

        func data() throws -> Data {
            let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
            let data = try encoder.encode(self)
            guard data.count <= 524_288 else { throw BindingError.oversized }
            return data
        }
        func filtered(to nodeIDs: Set<String>) -> Self {
            .init(schemaVersion: schemaVersion, sessionID: sessionID, originDigest: originDigest,
                  manifestSHA256: manifestSHA256, graphDigest: graphDigest,
                  bindings: bindings.filter { nodeIDs.contains($0.nodeID) })
        }
    }
    enum BindingError: Error { case invalidIdentity, invalidIDs, exhausted, oversized }
    private let manifestSHA256: String
    private let availableIDs: [UInt32]
    private var reservations: [String: Binding] = [:]
    private var reserved = Set<UInt32>()

    init(manifestSHA256: String, lowDetailIDs: [UInt32]) throws {
        guard Self.isDigest(manifestSHA256) else { throw BindingError.invalidIdentity }
        guard !lowDetailIDs.isEmpty, lowDetailIDs.count <= 50_000,
              Set(lowDetailIDs).count == lowDetailIDs.count else { throw BindingError.invalidIDs }
        self.manifestSHA256 = manifestSHA256
        availableIDs = lowDetailIDs
    }

    mutating func project(_ graph: CompanionGraphSnapshot, sessionID: String, originDigest: String) throws -> Sidecar {
        guard UUID(uuidString: sessionID) != nil, Self.isDigest(originDigest),
              graph.nodes.count <= CompanionGraph.maximumNodes,
              Set(graph.nodes.map(\.id)).count == graph.nodes.count,
              graph.nodes.allSatisfy({ !$0.id.isEmpty && $0.id.utf8.count <= 256
                  && !$0.id.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) }) else { throw BindingError.invalidIdentity }
        var bindings: [Binding] = []
        for node in graph.nodes.sorted(by: { $0.id < $1.id }) {
            if let existing = reservations[node.id] { bindings.append(existing); continue }
            let hash = Array(SHA256.hash(data: Data((manifestSHA256 + ":" + node.id).utf8)))
            let start = Int(hash.prefix(4).reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }) % availableIDs.count
            var cluster: [UInt32] = []
            for offset in 0..<availableIDs.count {
                let id = availableIDs[(start + offset) % availableIDs.count]
                if !reserved.contains(id) { cluster.append(id) }
                if cluster.count == 32 { break }
            }
            guard cluster.count == 32 else { throw BindingError.exhausted }
            let binding = Binding(nodeID: node.id, anchorID: cluster[0], particleIDs: cluster)
            reservations[node.id] = binding; reserved.formUnion(cluster); bindings.append(binding)
        }
        return .init(schemaVersion: 1, sessionID: sessionID, originDigest: originDigest,
                     manifestSHA256: manifestSHA256, graphDigest: Self.digest(graph), bindings: bindings)
    }

    static func isDigest(_ text: String) -> Bool {
        text.utf8.count == 64 && text.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
    }
    static func sha256(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
    static func digest(_ graph: CompanionGraphSnapshot) -> String {
        // Include availability and version details: a retained historical node
        // can become unavailable without changing its identity.
        var pieces = ["archi-point-knowledge-state/v1"]
        for node in graph.nodes.sorted(by: { $0.id < $1.id }) {
            pieces += [node.id, node.kind.rawValue, node.title, node.subtitle, node.status]
            for detail in node.details { pieces += [detail.label, detail.value] }
        }
        for edge in graph.edges.sorted(by: { $0.id < $1.id }) { pieces += [edge.id, edge.source, edge.target, edge.label] }
        return sha256(Data(pieces.map { "\($0.utf8.count):\($0)" }.joined().utf8))
    }
}

struct LiminalKnowledgeSelection: Codable {
    let schemaVersion: Int
    let sessionID: String
    let originDigest: String
    let revision: Int
    let manifestSHA256: String
    let graphDigest: String
    let nodeID: String
    let artParticleID: UInt32
    let sequence: Int
    let updatedAtUnix: Double

    func resolves(in sidecar: LiminalKnowledgeBindings.Sidecar, graph: CompanionGraphSnapshot,
                  revisions: Set<Int>, after sequence: Int, now: Date) -> CompanionGraphNode? {
        guard schemaVersion == 1, self.sequence > sequence, self.sequence > 0,
              sessionID == sidecar.sessionID, originDigest == sidecar.originDigest,
              manifestSHA256 == sidecar.manifestSHA256, graphDigest == sidecar.graphDigest,
              graphDigest == LiminalKnowledgeBindings.digest(graph), revisions.contains(revision),
              updatedAtUnix.isFinite, (-5...5).contains(now.timeIntervalSince1970 - updatedAtUnix),
              sidecar.bindings.contains(where: { $0.nodeID == nodeID && $0.particleIDs.contains(artParticleID) }) else { return nil }
        return graph.nodes.first { $0.id == nodeID }
    }
}
