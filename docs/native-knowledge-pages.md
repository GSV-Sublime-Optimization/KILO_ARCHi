# Source-linked knowledge pages

ARCHi's Memories screen now holds user-authored **claims** and **concepts** alongside their exact supporting passages. It uses the existing profile's ReadingSourceLibrary; Activity map is a derived view of that owner. No second app, vault, companion or model service is created.

## Working flow

1. Keep a reading copy in Work together, or use Add text file in Memories.
2. Choose New page. Write a title and note, choose Claim or Concept, and link one to four exact passages. Repeated quotations require choosing the occurrence. Using the entire kept copy is an explicit choice.
3. Save the draft, inspect its evidence, then Mark reviewed. This records your review, not factual certification.
4. Open the page from Activity map, revise it, inspect earlier versions, withdraw it, or explicitly Copy Markdown.

Pages are searchable by title, note, kind and state. Profile switching, restoration and normal Quit protect an open draft. Saving never overwrites the currently shared working copy. Copy Markdown writes to the macOS clipboard, which may be available to other apps and Universal Clipboard according to system settings.

## Exact dependency and correction rules

An anchor contains the retained source UUID, revision, SHA-256 digest, UTF-16 location/length and SHA-256 digest of the quoted passage. It stores no extra source text or original file path. Unicode boundaries and all ranges are validated. A page review binds the exact immutable page revision.

Source replacement or forgetting makes dependent reviewed pages unavailable for current use. The page keeps its authored note and hash/range references; unavailable source prose is never reconstructed. Make a new draft with fresh anchors before reviewing again. Withdrawing a page appends a revision; it is not erasure of authored history.

The graph shows only explicit page-to-source attribution. A link is not proof that the source entails the claim. Shared sources give inspectable backlinks, not an inferred semantic relationship.

## Persistence and bounds

The existing `preferences.reading-sources.json` gains schema `archi-reading-sources/v2`. Legacy v1 files load without writes and upgrade on the next authorized change. V2 includes bounded page history in the same atomic file transaction as the source copies. An old binary cannot read v2; preserve the installed app rollback and data backup when intentionally downgrading.

Bounds: eight kept copies, 100 KB per source, 400 KB total source text; page title 240 UTF-8 bytes, note 8,192 UTF-8 bytes, one to four anchors, 64 total page versions. Each active page reserves a future withdrawal slot. Full history is preserved and reported; no automatic pruning. File locking and exact disk-digest checks prevent stale windows from overwriting each other. Malformed schemas, duplicate keys and invalid histories block writes.

These reading copies and pages remain outside the current profile backup package. Keep explicit Markdown exports where needed; automatic backup inclusion remains unfinished.

## Hampton placement and present limit

This installs source-addressed authored memory and correction-aware dependency navigation in the existing native memory owner. It complements the already source-bound kept lessons and document methods. It does not conflate an authored claim, user review, an observed task outcome, or a certified skill.

Pages are not automatically injected into Qwen/Codex requests, converted to lessons, or counted as companion growth. Future assisted synthesis/retrieval must carry exact page-version and source dependencies through dispatch, result admission, correction and method reuse. Semantic entailment, skill transfer and research-theory validation remain separate work.

See [knowledge links](native-knowledge-links.md) for the source-grounded navigation design and [connected reading](native-connected-reading.md) for existing source-assisted document reasoning. This increment needs no puzzle execution, model call or paid API request.
