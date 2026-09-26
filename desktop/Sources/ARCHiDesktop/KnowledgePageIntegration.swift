import Foundation

@MainActor
extension CompanionStore {
    private var canChangeKnowledgePages: Bool {
        guard !isShuttingDown, !isWorking else {
            knowledgePageMessage = "Finish the current request before changing a knowledge page."
            return false
        }
        guard readingSources.loadError == nil, readingSources.isCurrentOnDisk else {
            knowledgePageMessage = readingSources.loadError ?? "The source library changed outside this window. Reopen before editing."
            return false
        }
        return true
    }

    func beginKnowledgePage(_ page: KnowledgePage? = nil) {
        guard canChangeKnowledgePages else { return }
        guard knowledgePageDraft == nil else {
            knowledgePageMessage = "Save or discard the open page draft first."
            open(.memory)
            return
        }
        if let page, !readingSources.latestKnowledgePages.contains(page) {
            knowledgePageMessage = "This page has a newer version. Open that version before revising."
            return
        }
        knowledgePageMessage = nil
        knowledgePageDraft = KnowledgePageDraft(prior: page)
        open(.memory)
    }

    @discardableResult
    func saveKnowledgePage(prior: KnowledgePage?, title: String, body: String,
                           kind: KnowledgePageKind, anchors: [KnowledgeAnchor]) -> Bool {
        guard canChangeKnowledgePages else { return false }
        do {
            let page = try readingSources.saveKnowledgePage(id: prior?.id, expectedRevision: prior?.revision,
                title: title, body: body, kind: kind, anchors: anchors)
            selectedKnowledgePageID = page.id
            knowledgePageDraft = nil
            knowledgePageMessage = "Draft saved on this Mac. Review its passages when ready."
            return true
        } catch {
            knowledgePageMessage = error.localizedDescription
            return false
        }
    }

    func reviewKnowledgePage(_ page: KnowledgePage) {
        guard canChangeKnowledgePages else { return }
        do {
            let reviewed = try readingSources.reviewKnowledgePage(id: page.id, expectedRevision: page.revision)
            selectedKnowledgePageID = reviewed.id
            knowledgePageMessage = "Your review is recorded. It does not certify the claim as true or teach a lesson automatically."
        } catch { knowledgePageMessage = error.localizedDescription }
    }

    func withdrawKnowledgePage(_ page: KnowledgePage) {
        guard canChangeKnowledgePages else { return }
        do {
            _ = try readingSources.withdrawKnowledgePage(id: page.id, expectedRevision: page.revision)
            knowledgePageMessage = "Page withdrawn. Earlier versions remain in its history."
        } catch { knowledgePageMessage = error.localizedDescription }
    }
}
