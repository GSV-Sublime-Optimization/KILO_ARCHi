# Reviewed concepts to document methods

26 September 2026 · R26-NATIVE-KNOWLEDGE-METHODS

ARCHi can keep an explicitly authored document-method candidate from a current,
reviewed **Concept** in Memories. It uses the existing source library, method
library, document journal, local Qwen owner, Q2E controller and Usage records.
There is no second app, identity store or learning database.

## Use it

1. Keep a source passage in Memories and author a Concept linked to that passage.
2. Review the concept. Expand **Create a document method candidate**.
3. Write the instruction you want to try, choose the length and exact-token
   requirements, and **Save candidate**. The instruction starts blank; ARCHi does
   not convert source prose into instructions automatically.
4. Share a working document in Chat, select a passage, and choose Revise with the
   same requirements. Select the candidate in Document methods and Send locally.
5. Inspect the proposed change. Apply is a separate action, followed by your
   Helpful or correction review of the applied result.

The page body and its quotations are not copied into this request. The explicit
method instruction and selected working document supply the model input. Exact
page and source versions remain native dependencies on the request and result.
The method details provide **Show source** and its original page version.

## Evidence and hardening

- A candidate has no fabricated applied result, helpful feedback or companion
  growth. Its first trial is distinct from evidence that it works.
- Knowledge-derived methods and descendants run locally. Codex, Compare and
  automatic external fallback cannot send these method requests. The direct
  Codex client also rejects the marked request.
- Page edits, withdrawal, source changes and on-disk changes invalidate use.
  Checks run at selection, dispatch, result admission, Apply and later feedback.
- Kept descendants retain the exact source binding. A revision cannot import a
  different bound concept through its supporting result. Starting a new method
  family preserves that distinct provenance instead.
- When source support becomes unavailable, previous attempts and feedback stay
  in history. The next Q2E evidence projection marks those observations unknown,
  so they no longer supply positive numerical adaptation. Costs remain retained.
- Method ranking uses only currently available methods; cost is compared only
  across compatible measured records. Unknown dollars or energy are not zero.
- Corrected and withdrawn method uses remain inspectable and block reuse through
  the existing library. Nothing here bypasses explicit Apply or grants authority
  to change permissions, model weights or companion identity.

## Hampton integration

This completes a bounded bridge from Stack R2's qualified memory into its task
and learning loops: attributed concept → authored candidate → local proposal →
checked applied result → reviewed outcome → current evidence projection.
`HamptonDocumentNumericalControl` replays accepted outcome observations through
the existing typed `HamptonNumericalDynamics` update. Redrawing the UI does not
advance a second state store, and a saved candidate is not a measured quotient.

The new work extends [local knowledge use](native-knowledge-chat.md).
It does not install the papers' theorem generators, physics calculations or
analog hardware. It also does not establish efficacy of the complete Hampton
theory, patent scope, cross-task transfer or automatic skill certification.

## Persistence and rollback

The method archive writes `archi-document-procedures/v3` and reads v1/v2 without
rewriting them just by opening. Older method bindings omit `knowledgeOrigin` and
remain byte-stable. Existing profile backups retain the method and source
sidecars. Preserve a current backup before reverting to an older app: an older
strict method reader cannot read a newly written v3 archive.

Q2E's frozen evidence gains an optional native source-availability flag. Existing
records and their digests remain unchanged; new decisions bind the current
assessment. Historical user feedback and measured resource observations are not
erased when its source changes.
