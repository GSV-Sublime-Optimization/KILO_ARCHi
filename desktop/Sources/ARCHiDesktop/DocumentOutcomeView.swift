import SwiftUI

/// The visible end of the existing observation/action/outcome loop. All mutations
/// remain with the journal, procedure and development owners used by history.
@MainActor
struct DocumentOutcomeView: View {
    @ObservedObject var store: CompanionStore
    let record: DocumentWorkRecord

    private var keptMethods: [DocumentProcedure] {
        store.documentProcedures.latestProcedures.filter {
            $0.originRecordID == record.id && $0.originFeedbackID == record.feedback?.id
                && store.documentProcedureUnavailable($0.binding) == nil
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Review this change", systemImage: "checkmark.bubble")
                .font(.headline)
            Text("The edit is in your working copy. Your review helps ARCHi choose its next approach.")
                .font(.caption).foregroundStyle(.secondary)
            DocumentFeedbackControls(store: store, record: record)
            if keptMethods.isEmpty {
                KeepDocumentProcedureView(store: store, record: record, startsExpanded: true)
            } else {
                ForEach(keptMethods) { method in
                    Label("Kept: \(method.title) · v\(method.revision)", systemImage: "bookmark")
                        .font(.caption.weight(.medium))
                }
                Text("Select another passage, choose Revise, then choose this method in Saved procedures. Review its instruction before Send.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                Button("Undo this edit") { store.undoWorkingCopyEdit() }
                    .disabled(!store.canUndoWorkingCopyEdit || store.isWorking)
                    .accessibilityIdentifier("document.outcome.undo")
                Button("Usage") { _ = store.openDocumentUsage(taskID: record.requestID) }
            }.buttonStyle(.borderless).font(.caption)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(WorkspaceTheme.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("document.current-outcome")
    }
}
