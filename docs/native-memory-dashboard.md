# Memory map and Home

The memory graph is a primary ARCHi destination under **Your companion**. Home puts it directly below the current companion, ahead of Arena and Marketplace. **Explore memory** opens the map; **Present map** opens a spacious, read-only view in the same app. **Manage memories** returns to the existing memory owner.

## Working with the map

- **Memory** shows retained sources, authored knowledge-page records, kept lessons, and their recorded connections. The companion is a visual anchor, not another remembered fact.
- **All activity** includes request receipts, temporary context, outcomes, usage and ARC evidence. Those records are not counted as new memories.
- Select a particle or use **List** to inspect status, source version and recorded backlinks. Knowledge pages still open their existing page inspector. Retained-source actions open the memory library rather than an unrelated shared working document.
- **Showcase** hides secondary controls and gives the canvas more room. Selecting a record reveals its inspector. **Exit showcase** or Escape restores controls. List and Fit remain accessible; active filters stay visible and can be cleared.
- Showcase is a local presentation mode. It displays the current profile's real titles and records. It does not anonymize them, create a public link, export a demo or add sample memories.

Home displays retained source-copy counts, latest page-record counts (including drafts and withdrawn pages), and valid non-expired kept lessons. Open a record to inspect its state. Removed source versions remain marked as unavailable references; they do not inflate the retained-source count. The small Home preview is static and bounded, with no model work or constant animation. The full map respects reduced motion.

## Ownership and continuity

`MemoryMapSnapshot` composes the existing `CompanionGraph` and `KnowledgePageGraph` projections. IDs, directed edges, review status and inspection targets remain owned by their existing records. No archive schema, profile store, model routing, permission or knowledge-admission rule changes.

The general Memory map route clears old deep-link selection. Exact activity-receipt routes still open the correct activity scope. Changing map scope does not recreate the graph's view state. Home's feature directory is collapsed by default; all destinations remain reachable through it and the sidebar.

## Qualification

The implementation was compiled on authored and curated sources. Fourteen focused projection/source/navigation checks passed; no models, puzzles or broad benchmark suite were run. Installed observations and profile preservation are recorded in [the delivery receipt](accountability/evidence/r29-memory-dashboard-2026-09-29.json).

This delivers a desktop navigation and presentation increment. iPhone parity, long-session dense-graph performance and the wider Alpha/Beta release blockers remain separately qualified. Showing a graph does not validate a research theory or establish learned capability.

The subsequent [intuitive Home refinement](native-intuitive-home.md) adds document review and saved-method access, a larger preview, and a **View options** popover. The original delivery receipt above remains historical.
