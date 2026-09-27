import SwiftUI

/// Local read projection; selected passages are revalidated by the existing
/// reading owner when drafting. No retrieval result can save or review a page.
@MainActor
struct KnowledgeRetrievalView: View {
    @ObservedObject var store: CompanionStore
    @State private var query = ""
    @State private var topic = ""
    @State private var result: KnowledgeRetrievalResult?
    @State private var selected: [KnowledgeAnchor] = []
    @State private var message: String?

    var body: some View {
        DisclosureGroup("Find connections in your reading") {
            VStack(alignment: .leading, spacing: 10) {
                Text("Search kept copies and reviewed pages. Matching words help locate passages; they do not establish whether a claim is true.")
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    TextField("Search sources and concepts", text: $query).textFieldStyle(.roundedBorder)
                        .onSubmit(search).accessibilityIdentifier("knowledge.retrieval.query")
                    Button("Find", action: search).disabled(query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .accessibilityIdentifier("knowledge.retrieval.search")
                }
                if let result {
                    Text("\(result.hits.count) of \(result.matchingCount) word matches · \(result.excludedPageCount) unavailable pages excluded")
                        .font(.caption).foregroundStyle(.secondary)
                    if result.isPartial {
                        Text("Results are bounded. Narrow the search to find omitted matches.").font(.caption).foregroundStyle(.orange)
                    }
                    ForEach(result.hits) { hit in
                        VStack(alignment: .leading, spacing: 5) {
                            Text(hit.title).font(.system(size: 12, weight: .medium))
                            Text(hit.kind == .page ? "Reviewed interpretation" : "Source passage · \(hit.sourceTitle ?? "Kept copy")")
                                .font(.caption2).foregroundStyle(.secondary)
                            DisclosureGroup("Read match") { Text(hit.text).font(.caption).textSelection(.enabled) }
                            if let anchor = hit.anchor {
                                let picked = selected.contains(anchor)
                                Button(picked ? "Remove passage" : "Use passage") {
                                    guard store.readingSources.quote(for: anchor) != nil else {
                                        message = "This passage changed. Search again."; return
                                    }
                                    if picked { selected.removeAll { $0 == anchor } }
                                    else if selected.count < 3 { selected.append(anchor) }
                                }.disabled(!picked && selected.count >= 3)
                            } else if let binding = hit.pageBinding {
                                Button("Open page") {
                                    guard store.knowledgeDependenciesAreCurrent([binding]) else {
                                        message = "This page changed or is no longer available. Search again."; return
                                    }
                                    store.selectedKnowledgePageID = binding.id
                                }
                            }
                        }.padding(10).background(.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 8))
                    }
                }
                if !selected.isEmpty {
                    Text("\(selected.count) selected passage(s) · exact versions remain linked").font(.caption)
                    TextField("Concept topic", text: $topic).textFieldStyle(.roundedBorder)
                        .accessibilityIdentifier("knowledge.concept.topic")
                    HStack {
                        Button("Draft concept locally") { _ = store.draftKnowledgeConcept(title: topic, anchors: selected) }
                            .disabled(store.isWorking || topic.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            .accessibilityIdentifier("knowledge.concept.draft")
                        Button("Clear selection") { selected = [] }.disabled(store.isWorking)
                        if store.isDraftingKnowledgeConcept {
                            Button("Stop") { store.discardKnowledgeConceptDraft() }
                        }
                    }
                }
                if let draft = store.currentKnowledgeConceptDraft {
                    Text(draft.title).font(.headline)
                    Text(draft.body).font(.caption).textSelection(.enabled)
                    HStack {
                        Button("Review in editor…") { store.editKnowledgeConceptDraft() }
                            .accessibilityIdentifier("knowledge.concept.review")
                        Button("Discard") { store.discardKnowledgeConceptDraft() }
                    }
                    Text("Generated interpretation. Saving creates a draft; reviewing it is a separate action.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if let status = store.knowledgeConceptDraftMessage { Text(status).font(.caption).foregroundStyle(.secondary) }
                if let message { Text(message).font(.caption).foregroundStyle(.orange) }
            }.padding(.vertical, 10)
        }.accessibilityIdentifier("knowledge.retrieval")
    }
    private func search() {
        do {
            result = try KnowledgeRetrieval.search(query: query, sources: store.readingSources.sources,
                pages: store.readingSources.knowledgePages, libraryIsCurrent: store.readingSources.isCurrentOnDisk)
            message = nil
        } catch { result = nil; message = error.localizedDescription }
    }
}
