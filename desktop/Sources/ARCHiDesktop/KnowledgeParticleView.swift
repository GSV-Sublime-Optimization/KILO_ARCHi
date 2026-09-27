import SwiftUI

/// One luminous particle per current graph record. Only recorded edges are drawn.
struct KnowledgeParticleView: View {
    let field: KnowledgeParticleField
    let nodes: [CompanionGraphNode]
    let selectedID: String?
    let spread: Double
    let pulses: Bool
    let reduceMotion: Bool
    let tint: Color
    let onSelect: (String) -> Void
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var hoveredID: String?

    var body: some View {
        let still = reduceMotion || systemReduceMotion
        let visible = Set(nodes.map(\.id))
        let particles = field.particles.filter { visible.contains($0.nodeID) }
        let edges = field.edges.filter { visible.contains($0.source) && visible.contains($0.target) }
        let active = hoveredID.flatMap { visible.contains($0) ? $0 : nil }
            ?? selectedID.flatMap { visible.contains($0) ? $0 : nil }
        let neighbours = Set(edges.filter { $0.source == active || $0.target == active }.flatMap { [$0.source, $0.target] })
        GeometryReader { proxy in
            let scale = min(proxy.size.width, proxy.size.height) * 0.43
            let center = CGPoint(x: proxy.size.width / 2, y: proxy.size.height / 2)
            let points = Dictionary(uniqueKeysWithValues: particles.map { particle in
                let p = KnowledgeParticleField.position(particle, spread: spread, reduceMotion: still)
                return (particle.nodeID, CGPoint(x: center.x + p.x * scale, y: center.y + p.y * scale))
            })
            ZStack {
                TimelineView(.animation(minimumInterval: 1 / 15, paused: still || !pulses || scenePhase != .active)) { tick in
                    let time = still || !pulses ? 0 : tick.date.timeIntervalSinceReferenceDate
                    Canvas { context, size in
                        // A diffuse, non-node halo. It is not an extra memory particle.
                        context.fill(Path(ellipseIn: CGRect(x: center.x - scale * 0.70, y: center.y - scale * 0.70,
                            width: scale * 1.40, height: scale * 1.40)), with: .radialGradient(
                                Gradient(colors: [tint.opacity(0.08), .clear]), center: center, startRadius: 0, endRadius: scale * 0.70))
                        for edge in edges {
                            guard let a = points[edge.source], let b = points[edge.target] else { continue }
                            let highlighted = edge.source == active || edge.target == active
                            var line = Path(); line.move(to: a); line.addLine(to: b)
                            context.stroke(line, with: .color(highlighted ? tint.opacity(0.80) : Color.secondary.opacity(active == nil ? 0.26 : 0.10)), lineWidth: highlighted ? 1.4 : 0.6)
                            if highlighted {
                                let angle = atan2(b.y - a.y, b.x - a.x)
                                let tip = CGPoint(x: a.x + (b.x - a.x) * 0.66, y: a.y + (b.y - a.y) * 0.66)
                                var arrow = Path(); arrow.move(to: CGPoint(x: tip.x - cos(angle - 0.5) * 5, y: tip.y - sin(angle - 0.5) * 5))
                                arrow.addLine(to: tip); arrow.addLine(to: CGPoint(x: tip.x - cos(angle + 0.5) * 5, y: tip.y - sin(angle + 0.5) * 5))
                                context.stroke(arrow, with: .color(tint.opacity(0.8)), lineWidth: 1)
                            }
                        }
                        for particle in particles {
                            guard let point = points[particle.nodeID] else { continue }
                            let focused = particle.nodeID == active || neighbours.contains(particle.nodeID)
                            let color = particle.kind == .companion ? tint : graphColor(particle.kind)
                            let pulse = still || !pulses ? 1 : 0.86 + 0.14 * sin(time * 0.8 + particle.phase)
                            let radius = particle.kind == .companion ? 7.0 : 3.7
                            let opacity = active == nil || focused ? pulse : 0.36
                            context.fill(Path(ellipseIn: CGRect(x: point.x - radius * 4, y: point.y - radius * 4,
                                width: radius * 8, height: radius * 8)), with: .radialGradient(
                                    Gradient(colors: [color.opacity(0.45 * opacity), .clear]), center: point, startRadius: 0, endRadius: radius * 4))
                            context.fill(Path(ellipseIn: CGRect(x: point.x - radius, y: point.y - radius,
                                width: radius * 2, height: radius * 2)), with: .color(color.opacity(opacity)))
                            context.fill(Path(ellipseIn: CGRect(x: point.x - 1.2, y: point.y - 1.2, width: 2.4, height: 2.4)), with: .color(.white.opacity(opacity)))
                            if particle.nodeID == selectedID {
                                context.stroke(Path(ellipseIn: CGRect(x: point.x - 11, y: point.y - 11, width: 22, height: 22)), with: .color(color), lineWidth: 1)
                            }
                        }
                    }.accessibilityHidden(true)
                }.allowsHitTesting(false)
                ForEach(nodes) { node in
                    if let position = points[node.id] {
                        nodeButton(node).position(position)
                        if node.id == active || (nodes.count <= 12 && spread > 0.75) {
                            Text(node.title).font(.system(size: 10, weight: .medium)).lineLimit(1)
                                .padding(.horizontal, 5).padding(.vertical, 3)
                                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 5))
                                .frame(maxWidth: 145).position(x: position.x, y: position.y + 23)
                                .allowsHitTesting(false).accessibilityHidden(true)
                        }
                    }
                }
            }
        }.accessibilityIdentifier("companion-graph.particles")
    }

    private func nodeButton(_ node: CompanionGraphNode) -> some View {
        Button { onSelect(node.id) } label: {
            Circle().fill(Color.clear).frame(width: 24, height: 24).contentShape(Circle())
        }
        .buttonStyle(.plain).help("\(node.title) · \(node.status)")
        .accessibilityLabel("\(node.kind.title): \(node.title). \(node.status)")
        .accessibilityAddTraits(node.id == selectedID ? [.isSelected] : [])
        .accessibilityIdentifier("companion-graph.particle.\(node.id)")
        .onHover { isHovered in
            if isHovered { hoveredID = node.id }
            else if hoveredID == node.id { hoveredID = nil }
        }
    }
}
