import SwiftUI

/// A reviewed concept can inspire an explicitly authored method. Its prose stays
/// in the reading library; saving a candidate neither sends nor applies work.
@MainActor
struct KnowledgeProcedureCandidateView: View {
    @ObservedObject var store: CompanionStore
    let page: KnowledgePage
    @State private var expanded = false
    @State private var title: String
    @State private var instruction = ""
    @State private var requirements = DocumentWorkRequirements()
    @State private var saveMessage: String?

    init(store: CompanionStore, page: KnowledgePage) {
        self.store = store
        self.page = page
        _title = State(initialValue: page.title)
    }

    private var identifier: String { "\(page.id).\(page.revision)" }
    private var trimmedTitle: String { title.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var trimmedInstruction: String { instruction.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var textIssue: String? {
        if trimmedTitle.count > 80 {
            return "Shorten the method name to 80 characters or fewer."
        }
        if trimmedInstruction.count > 1_200 {
            return "Shorten the instruction to 1,200 characters or fewer."
        }
        if trimmedTitle.utf8.count > 320 || trimmedInstruction.utf8.count > 4_800 {
            return "Shorten the name or instruction; it exceeds the saved-method size limit."
        }
        let unsupported = CharacterSet.controlCharacters.subtracting(.newlines)
        if (trimmedTitle + trimmedInstruction).unicodeScalars.contains(where: unsupported.contains) {
            return "Remove unsupported control characters before saving."
        }
        return nil
    }
    private var canSave: Bool {
        store.canKeepDocumentProcedure
            && page.state == .reviewed && page.kind == .concept
            && store.readingSources.availability(of: page) == nil
            && !trimmedTitle.isEmpty && !trimmedInstruction.isEmpty && textIssue == nil
    }

    var body: some View {
        DisclosureGroup("Create a document method candidate", isExpanded: $expanded) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Write an instruction worth trying on a selected passage. Saving keeps your method and a link to this reviewed concept on this Mac.")
                    .foregroundStyle(.secondary)
                TextField("Method name", text: $title)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("knowledge.procedure-name.\(identifier)")
                TextField("Instruction for a later selected passage", text: $instruction, axis: .vertical)
                    .textFieldStyle(.roundedBorder).lineLimit(3...8)
                    .accessibilityIdentifier("knowledge.procedure-instruction.\(identifier)")
                Toggle("Require shorter text", isOn: $requirements.mustBeShorter)
                    .accessibilityIdentifier("knowledge.procedure-shorter.\(identifier)")
                Toggle("Keep exact numbers and links", isOn: $requirements.preserveNumbersAndLinks)
                    .accessibilityIdentifier("knowledge.procedure-exact-tokens.\(identifier)")
                Text("Untested candidate · no demonstrated usefulness yet. Choose it for a passage, review the proposed edit, then record the applied outcome.")
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("knowledge.procedure-candidate-status.\(identifier)")
                Text("Saving sends nothing. The page body and supporting passages are not copied into the instruction. Methods from knowledge pages run locally on this Mac.")
                    .foregroundStyle(.secondary)
                if let textIssue {
                    Text(textIssue).foregroundStyle(.orange)
                        .accessibilityIdentifier("knowledge.procedure-text-issue.\(identifier)")
                }
                if let unavailable = store.readingSources.availability(of: page) {
                    Text(unavailable).foregroundStyle(.orange)
                        .accessibilityIdentifier("knowledge.procedure-availability.\(identifier)")
                }
                Button("Save candidate") {
                    if store.keepKnowledgeProcedure(page: page, title: title,
                                                    instruction: instruction, requirements: requirements) {
                        title = ""
                        instruction = ""
                        requirements = DocumentWorkRequirements()
                    }
                    saveMessage = store.knowledgePageMessage
                }
                .buttonStyle(.bordered).disabled(!canSave)
                .accessibilityIdentifier("knowledge.save-procedure.\(identifier)")
                if let saveMessage {
                    Text(saveMessage).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("knowledge.procedure-save-status.\(identifier)")
                }
            }.padding(.top, 6)
        }
        .font(.system(size: 11))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("knowledge.procedure-candidate.\(identifier)")
    }
}
