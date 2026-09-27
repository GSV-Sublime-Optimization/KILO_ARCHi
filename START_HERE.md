# Start Here — ARCHi

ARCHi is a local-first companion workspace with a native macOS application, a Unity companion/practice surface, and a local creator marketplace.

This repository is a **source candidate**, not a Beta declaration, signed distribution, or proof that every presentation asset is redistributable.

## Read first

1. `.gsv/project.yaml`
2. `README.md`
3. `docs/ARCHITECTURE.md`
4. `docs/ALPHA_VALIDATION.md`
5. `CONTRIBUTING.md`
6. the narrow subsystem document for the change

## Authority map

Keep these owners distinct:

- **Native Swift** owns assistance requests, permissions, working-copy state, kept lessons, saved preferences and companion development.
- **Unity** presents accepted companion state and local Arena/practice behavior. It does not own native memory, identity, or saved development.
- **Retained TypeScript Journey/battle code** keeps its existing game-domain ownership.
- **Marketplace** owns local accounts, creator listings and acquired inventory within its bounded service contract.
- **Qwen / Codex / Compare** are inference routes. They do not become identity, memory, permission, or canonical-state owners.
- **Node Lab** is a projection over current metadata and receipts, not an inferred relationship database or new persistence authority.

## Smallest useful verification

For source-only changes, run the narrowest applicable checks first.

Core source gates documented by this repository:

```sh
npm ci
npm run check
swift build --package-path desktop
swift test --package-path desktop
python3 -m unittest discover -s scripts/tests -p 'test_*source*.py' -v
python3 -m unittest discover -s marketplace/tests -v
```

Unity requires the pinned editor and its own build/interaction proof. A passing source build does not prove runtime interaction, accessibility, signing, notarization, another-Mac install, or redistribution clearance.

## Release truth

Do not collapse these into one word such as “ready”:

```text
source parses/builds
!= focused tests pass
!= native UI acceptance
!= Unity player acceptance
!= asset redistribution cleared
!= signed/notarized distribution
!= Beta/release declaration
```

Read `docs/ALPHA_VALIDATION.md` before making release claims.

## Agent rules

- preserve one owner per state/permission question;
- never silently copy private profiles, conversations, lessons, research, model weights or authoring originals into the source packet;
- never treat a copied UID, source recipe or local catalog item as creator endorsement or authenticated ownership;
- never turn provider fallback into a retry loop;
- distinguish proposal/review from Apply/Keep/persistence;
- do not “repair” missing withheld artwork by inventing or copying private assets;
- preserve third-party notices and asset provenance.

## Handoff

Leave:

```text
repo + branch + exact head
subsystem/authority touched
commands actually run
highest evidence rung proven
known skips/withheld resources
release/redistribution claims explicitly not proven
next deterministic command
```
