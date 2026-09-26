import Foundation

@MainActor
extension CompanionStore {
    var currentKnowledgeContext: KnowledgePageContext? {
        guard !selectedKnowledgePages.isEmpty, knowledgeDependenciesAreCurrent(selectedKnowledgePages) else { return nil }
        let pages = selectedKnowledgePages.compactMap { binding in
            readingSources.latestKnowledgePages.first { $0.binding == binding }
        }
        let quotes = pages.map { $0.anchors.compactMap { readingSources.quote(for: $0) } }
        return KnowledgePageContext.make(pages: pages, quotes: quotes)
    }

    var selectedKnowledgePageIssue: String? {
        guard !selectedKnowledgePages.isEmpty else { return nil }
        guard knowledgeDependenciesAreCurrent(selectedKnowledgePages) else {
            return "A selected page or its supporting source changed. Review and select the current version, or detach the pages."
        }
        return currentKnowledgeContext == nil ? "Selected pages and passages exceed the local context limit. Use fewer or shorter passages." : nil
    }

    func knowledgeDependenciesAreCurrent(_ bindings: [KnowledgePageBinding]?) -> Bool {
        guard let bindings else { return true }
        guard KnowledgePageBinding.valid(bindings), readingSources.isCurrentOnDisk else { return false }
        return bindings.allSatisfy { binding in
            guard let page = readingSources.latestKnowledgePages.first(where: { $0.binding == binding }) else { return false }
            return readingSources.availability(of: page) == nil
        }
    }

    func lessonDependenciesAreCurrent(_ origin: LessonOrigin?) -> Bool {
        readingDependenciesAreCurrent(origin?.readingSources) && knowledgeDependenciesAreCurrent(origin?.knowledgePages)
    }

    func useKnowledgePageInChat(_ page: KnowledgePage) {
        guard !isShuttingDown, knowledgePageDraft == nil else { return }
        guard readingSources.availability(of: page) == nil else {
            knowledgePageMessage = readingSources.availability(of: page); return
        }
        var next = selectedKnowledgePages.filter { $0.id != page.id }
        guard next.count < 4 else { knowledgePageMessage = "Use up to four pages at once."; return }
        next.append(page.binding)
        invalidateReadingContext(reason: "Selected knowledge pages for local chat. Nothing sent yet.")
        requestsRevision = false
        selectedKnowledgePages = next
        setAssistantRoute(.automatic)
        knowledgePageMessage = "Selected for local chat. Your shared document stays unchanged and is not sent with these pages."
        open(.assistant)
    }

    func detachKnowledgePages() {
        guard !isShuttingDown else { return }
        invalidateReadingContext(reason: "Knowledge pages detached. Earlier page context was cleared.")
        selectedKnowledgePages = []
    }

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
            invalidateReadingContext(reason: "Knowledge page saved. Earlier answer context was cleared.")
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
            invalidateReadingContext(reason: "Knowledge page reviewed. Earlier answer context was cleared.")
            knowledgePageMessage = "Your review is recorded. It does not certify the claim as true or teach a lesson automatically."
        } catch { knowledgePageMessage = error.localizedDescription }
    }

    func withdrawKnowledgePage(_ page: KnowledgePage) {
        guard canChangeKnowledgePages else { return }
        do {
            _ = try readingSources.withdrawKnowledgePage(id: page.id, expectedRevision: page.revision)
            invalidateReadingContext(reason: "Knowledge page withdrawn. Earlier answer context was cleared.")
            knowledgePageMessage = "Page withdrawn. Earlier versions remain in its history."
        } catch { knowledgePageMessage = error.localizedDescription }
    }
}
