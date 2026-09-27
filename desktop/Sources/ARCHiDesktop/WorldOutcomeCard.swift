import SwiftUI

@MainActor
struct WorldOutcomeCard: View {
    @ObservedObject var connection: UnityPresentationConnection

    var body: some View {
        WorkspaceCard {
            VStack(alignment: .leading, spacing: 10) {
                Label("Practice outcomes", systemImage: "arrow.triangle.branch").font(.headline)
                Text(connection.worldOutcomeStatus).font(.callout).foregroundStyle(.secondary)
                    .accessibilityIdentifier("arena.outcomes-status")
                if connection.missingWorldOutcomes > 0 {
                    Text("\(connection.missingWorldOutcomes) actions were missed between updates. This is an incomplete session history.")
                        .font(.caption).foregroundStyle(.orange)
                }
                if !connection.worldOutcomes.isEmpty {
                    DisclosureGroup("Recent actions · \(connection.worldOutcomes.count)") {
                        ForEach(connection.worldOutcomes.reversed()) { outcome in
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Round \(outcome.round) · \(outcome.action.capitalized) → \(outcome.damageDealt) dealt, \(outcome.damageTaken) taken")
                                    .font(.callout)
                                Text("Integrity \(outcome.integrityBefore) → \(outcome.integrityAfter) · Spark \(outcome.sparkBefore) → \(outcome.sparkAfter) · rival \(outcome.rivalAction)")
                                    .font(.caption).foregroundStyle(.secondary)
                                if outcome.complete {
                                    Text(outcome.winner == "one" ? "Practice win" : outcome.winner == "two" ? "Practice loss" : "Practice draw")
                                        .font(.caption)
                                }
                                Text("Action \(outcome.actionID.prefix(8)) · session sequence \(outcome.sequence) · \(Date(timeIntervalSince1970: outcome.atUnix).formatted(date: .omitted, time: .standard))")
                                    .font(.caption2).foregroundStyle(.secondary).textSelection(.enabled)
                            }.padding(.vertical, 6)
                        }
                    }
                }
                Text("Unity rule outcomes from your solo inputs. They do not certify a skill, change saved growth or confirm a real-world action. Up to 32 recent actions stay for this session.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }.accessibilityElement(children: .contain).accessibilityIdentifier("arena.outcomes")
    }
}
