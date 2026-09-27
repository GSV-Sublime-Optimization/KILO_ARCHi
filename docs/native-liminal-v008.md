# Liminal v008 — one knowledge-particle presentation

This increment connects an authenticated Houdini point package to the existing
desktop, Companion room and Arena presentation owners. It does not create a new
companion, profile store, memory store, or evolution rule.

**Activation remains blocked until the real v008 package and both renderer
endpoint reviews qualify.** Existing Liminal/KIN appearances remain available.
An exporter, a compiled renderer, and synthetic contract checks do not establish
the completed visual upgrade or a 30 fps result.

## Source and quality

The [point-asset contract](liminal-point-asset-v1.md) pins the v008 HIP and the
pre-strip choreography node. The exporter preserves a copied source/dependency
tree, retains the 800,000-point endpoint master, and produces nested 50k, 100k,
and 200k IDs and 120 sampled frames. It measures bounded motion and half-frame
interpolation error against the source cook. v002 exports are rejected.

[The research register](research/liminal-rendering-techniques-2026-09-27.md)
records the official documentation, GitHub references and implementation
decisions. No third-party example art or renderer code was imported.

## Runtime ownership

- `LiminalPointAsset` authenticates the package and samples. Metal and Unity use
  the same positions, linear colors, radius, emission, camera convention and
  nested point IDs. Explicit GPU snapshots replace SwiftUI capture of Metal.
- `LiminalV008Runtime` accepts only a bundled package plus a matching separate
  qualification receipt. The existing appearance preference selects it; pose
  is an optional, backward-compatible scalar in the existing preference file.
- `UnityPresentationConnection` sends a small versioned descriptor and receives
  actual point-renderer acknowledgments. Assets stay outside the heartbeat.
  An older helper cannot acknowledge a selected v008 appearance as rendered.
- `LiminalKnowledgeBindings` projects current graph records onto disjoint
  clusters of existing art IDs. Filtering does not reassign clusters. Retired
  IDs remain reserved during the session. This map is disposable presentation
  state, not a second source of knowledge.
- Inspection returns the record ID, asset hash, graph digest, session, revision,
  sequence and timestamp. Native code resolves the current record again before
  opening its existing source/version/backlink inspector. Stale or corrected
  selections cannot silently open a different record. Arena inspection blocks
  gameplay inputs.
- Activity only changes bounded light intensity. Motion and pose do not alter
  memory, permissions, capability measurements or evolution. Seed cursor,
  equipment, personal palette, hide/show and reduced motion retain their owners.

## Authoring and installation

Run the self-contained exporter and validator together with Houdini's `hython`
on the existing authoring machine. Exact commands and dependency pins are in the
contract. Use `--render-endpoints` for deterministic transparent source-data
reference images; these images do not themselves establish native/Unity visual
equivalence. Compare both renderers before recording endpoint approval.

Once source and renderer review evidence exists, prepare a separate JSON receipt
with `schemaVersion: 1`, `assetID: "liminal-v008"`, the exact `manifestSHA256`,
and explicit Boolean fields `sourceCooked`, `nativeEndpointsPassed`,
`unityEndpointsPassed`, `installedWalkthroughPassed`. The first three must be
true to stage activation. Do not mark the installed walkthrough true in advance.

The existing guarded builder accepts `ARCHI_LIMINAL_PACKAGE` and
`ARCHI_LIMINAL_QUALIFICATION`. `script/package_liminal_v008.py` validates the
source and both copied destinations before placing the receipt. The native
Resources and internal Unity StreamingAssets copies have identical manifests.
Later native updates preserve the installed qualified asset by default.

The existing updater owns app replacement, signing checks and rollback. It
does not change profile data. Keep a new candidate separate until its endpoint
review passes, then install through that updater. Do not activate by editing a
profile or claiming an arbitrary file path is qualified.

## Completion evidence still required

Record actual source cooking, native/Unity endpoint comparisons, intermediate
motion, transparent light/dark framing and selectable record resolution. Then
exercise desktop → Arena → desktop, restart, profile switching, personal
colors, reduced motion, missing assets and hidden suspension. Measure 30 fps
with automatic detail reduction on the installed app. Preserve existing release
blockers. No model calls, puzzle sessions or broad benchmark run is required.
