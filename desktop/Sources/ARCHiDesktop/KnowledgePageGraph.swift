import Foundation
import CryptoKit

/// Derived navigation over the existing source library. Edges record attribution,
/// not semantic entailment, model retrieval, or evidence of companion development.
@MainActor
enum KnowledgePageGraph {
    static func append(to base: CompanionGraphSnapshot, library: ReadingSourceLibrary) -> CompanionGraphSnapshot {
        var nodes = base.nodes, edges = base.edges, truncated = base.truncatedCount
        var ids = Set(nodes.map(\.id)), edgeIDs = Set(edges.map(\.id))
        func add(_ node: CompanionGraphNode) -> Bool {
            if ids.contains(node.id) { return true }
            guard nodes.count < CompanionGraph.maximumNodes else { truncated += 1; return false }
            nodes.append(node); ids.insert(node.id); return true
        }
        func link(_ from: String, _ to: String, _ label: String) {
            let id = key(["edge", from, to, label])
            guard !edgeIDs.contains(id) else { return }
            guard ids.contains(from), ids.contains(to), edges.count < CompanionGraph.maximumEdges else {
                truncated += 1; return
            }
            edges.append(.init(id: id, source: from, target: to, label: label)); edgeIDs.insert(id)
        }
        for page in library.latestKnowledgePages.sorted(by: { $0.id < $1.id }) {
            let id = key(["knowledge", page.id, String(page.revision)])
            let issue = library.availability(of: page)
            let stale = !page.anchors.allSatisfy { library.quote(for: $0) != nil }
            let status = page.state == .withdrawn ? "Withdrawn" : stale ? "Needs source review" : issue == nil ? "Reviewed · current sources" : page.state.title
            guard add(.init(id: id, title: page.title, subtitle: "\(page.kind.title) · v\(page.revision)",
                kind: .knowledge, status: status,
                details: [.init(label: "Your note", value: page.body),
                    .init(label: "Availability", value: issue ?? "Source passages are current. User review is not factual certification."),
                    .init(label: "Meaning", value: "This authored page is not automatically supplied to a model or counted as learning.")],
                target: .knowledgePage(id: page.id))) else { continue }
            if ids.contains("companion-archi") { link("companion-archi", id, "authored memory") }
            for anchor in page.anchors {
                let sourceID = key(["knowledge-source", anchor.source.id, String(anchor.source.revision), anchor.source.digest])
                let current = library.isCurrentOnDisk ? library.sources.first { $0.binding == anchor.source } : nil
                let sourceDetails: [CompanionGraphDetail] = [
                    .init(label: "Source ID", value: anchor.source.id),
                    .init(label: "Revision", value: String(anchor.source.revision)),
                    .init(label: "Digest", value: anchor.source.digest),
                    .init(label: "State", value: current == nil ? "Exact source no longer available. Historical text is not reconstructed." : "Exact retained source version. Inspect linked passages in the page.")]
                guard add(.init(id: sourceID, title: current?.title ?? "Unavailable source version",
                    subtitle: "Source v\(anchor.source.revision)", kind: .source,
                    status: current == nil ? "Needs source review" : "Retained source",
                    details: sourceDetails, target: nil)) else { continue }
                link(id, sourceID, "source passage")
            }
        }
        return .init(nodes: nodes, edges: edges, truncatedCount: truncated)
    }

    private static func key(_ parts: [String]) -> String {
        let bytes = Data(parts.map { "\($0.utf8.count):\($0)" }.joined().utf8)
        return SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
    }
}
