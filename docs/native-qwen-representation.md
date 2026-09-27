# Local Qwen representation integration — 2026-09-26

## Current increment

The existing Qwen3.5:9b GGUF now loads through a separate, exactly identified text adapter. A bounded local probe acquired one finite 4,096-value residual at `l_out-15`, using 124 input tokens and zero generated tokens in 15.55 seconds. The adapter is grounded in pinned Ollama compatibility source and preserves the original model bytes. It remains separate from the bundled native backend: successful extraction alone does not qualify a reader. [Adapter and provenance](../research/representation/gguf/compatibility-and-qualification.md).

Native v2 reader import now requires the complete supplied qualification record: a frozen plan matching the model, layer, template and backend; eligible corpus provenance; numeric weights bound to the report; all 16 calibration/holdout results and their recomputed margins; positive calibration separation; and fixed acceptance rules. A headline pass is insufficient. Legacy readers remain available for inspection but cannot enable measurements. These are consistency checks on supplied evidence, not authentication or independent scientific reproduction.

The fitting workflow accepts a bounded, frozen external synthetic corpus, derives support labels from its exact records, and rejects altered plans, requests or source inputs before invoking the worker. Previously disclosed built-in examples are permanently marked development-only and cannot emit a reader. External provenance does not prove examples were never seen elsewhere. Ordinary Qwen remains available while experimental measurement is off.

The new frozen Qwen3.5 attempt completed all 24 prefills in 58.88 seconds, using 3,234 input tokens and zero generated tokens. Fitting failed: calibration separation was −0.315378 and 6/8 held-out examples were correct. The fixed gate required positive separation and every calibration/holdout margin at least 0.1. No reader was exported or enabled. This uses a different corpus from the earlier 4/8 Qwen3 run; it is not a measured improvement over that run. The scoped loader now works, while measurement reliability remains unqualified. No retries or threshold changes followed.

## Earlier implementation and qualification record

ARCHi has an installed native adapter targeting its existing Qwen GGUF models, using a locally built Apple Silicon CPU runtime. The delivered increment includes bounded synthetic activation acquisition, a separate fitting workflow, scoped v2 reader imports and session-only report-review source. The Qwen3:8b acquisition completed, but the fitted reader failed its predeclared qualification gate. No reader was produced or enabled. Qwen3.5:9b has a separate loader incompatibility. Delivery, report-viewer interaction and reader qualification are separate results.

## Everyday use

Settings → Connections → Qwen → **Read-only model measurements** exposes the bundled runtime, an explicit reader import, and a toggle for this visit. Standard Qwen remains the default. A reader must match the selected reasoning model, GGUF bytes, fixed prompt template, runtime revision, hidden width and layer. Current source distinguishes legacy unqualified v1 imports from v2 readers carrying a supported limited shadow report. Import validates format, identities and report consistency; it does not independently authenticate the report or establish general calibration quality.

Connect validates the local manifest/config, blob location and worker protocol without loading model weights. Send starts the CPU model and hashes its actual GGUF bytes before inference. No extra model download is needed. This initial CPU path may be substantially slower than Ollama; the existing 180-second reply limit remains in force. No successful real-model measured reply or performance improvement has yet been established for this increment.

Measurement selection is temporary. Switching it stops local work, clears temporary local context and rebuilds the existing local assistant. Closing ARCHi resets the selection. Saved Seeds, appearance, personal profiles and retained memories keep their existing owners.

While measurements are enabled, the native store blocks external providers and Compare before connection, budget reservation or dispatch, and disables automatic external fallback, including timeout fallback. Turning measurements off retains ordinary Qwen and chat routing.

**Review calibration report…** opens a bounded report preview for this visit, including failed qualifications. It displays the supplied result, split counts, measurement scope, margins, limitations and selected-file digest. Reviewing a report does not import a reader, enable measurements, call a model or change companion state. The report-review source is installed; completing the picker and viewing the result in the UI remains unverified. A digest identifies the selected bytes and does not authenticate the report's claims.

## Where it connects

`CompanionStore → HamptonReasonsAssistant → GGUFRepresentationClient → bundled archi-gguf-shadow → existing answer validation → native invocation receipt`.

Only the reasoning role uses this opt-in adapter. Optional context selection continues through the existing Ollama role. ARC's deterministic tools are unchanged. Local work is still charged to the existing Token Steward local-work receipts, using actual reported token counts. There is no paid API transport or second identity/memory database.

One selected `l_out-N` residual tensor is projected onto one supplied reader direction. The normal reply worker returns scalar samples, not raw activations. Native receipts bind the answer, request, model, prompt components, measurement scope, token rule, reader/calibration labels and SHA-256 of the actual imported reader file. For v2 `prompt-last` readers the client requires exactly one sample at the final input-token position; later generated-token states are outside that calibrated position. These values never count as Helpful feedback, learned capability, truth, or permission.

## Bounded calibration source

[`calibrate.py`](../research/representation/gguf/calibrate.py) has explicit prepare, acquire and fit stages. Its frozen target is whether a supplied synthetic record contains the exact field requested for that record. Twelve matched pairs yield eight fitting examples, eight calibration examples and eight untouched holdout examples, separated by source group and prompt family. Positive/negative members preserve their word inventory while record IDs exchange the supporting and distractor rows.

The [acquisition contract](../research/representation/gguf/calibration-acquisition.md) describes a separate research-only command: one verified model load, a fresh context for each of at most 24 prefills, no generated tokens, no steering, and one final-prompt residual from `l_out-15`. Limits are 512 input tokens per sample, 8,192 total and a 540-second acquisition deadline with bounded teardown. Raw vectors are returned only to the local fitting workflow, not to native answer receipts or Token Steward.

The current fitting plan selects `mean_contrast_reader` in advance, uses fitting data for direction/center and calibration data for offset/scale, then freezes the numerical payload before evaluating holdout. Passing requires strict calibration separation and a signed standardized margin of at least `0.1` on every calibration and holdout example. No search or retry uses heldout results. A completed failed qualification keeps its report and emits no reader; acquisition or numerical failure cannot emit a reader either.

Only a pass produces `archi-gguf-reader/v2` with scope `synthetic-record-field-support/prompt-final/v1`, `tokenRule: prompt-last`, and a content-bound calibration report. The native importer checks a declared `limited-shadow-pass`, bounded split counts and a perfect reported holdout result. The UI calls this a **supplied limited shadow report**: checking its bytes and structure is different from independently reproducing it. Four held-out synthetic groups cannot qualify ordinary chat, general source relevance, honesty, truth detection, answer quality or performance gains.

The [R3 intake note](research/2026-09-25-stack-and-representation/r3-reference-intake.md) reinforces task-specific measurement, independent outcomes and evaluation rules. Its 20,000-character conversation preview and unrecovered atlas are research context, not an additional validation result for this reader.

## Current acquisition status and history

The earlier GGUF increment established source/transport and delivery evidence without a fitted reader or real-model measured-answer result. The final runtime refresh from `output/gguf-calibration-runtime-2026-09-25/runtime` is installed. The [installation receipt](../output/reader-calibration-2026-09-25/installation.json) records executable SHA-256 `8855631e8c73c20c5054f22caa0f5f5adcb4ef0f4a6b5ac072d4cfbfec7681a3`, matching runtime hashes, passing signature verification, and seven known profile files plus 218 Unity resources unchanged; the [install log](../output/reader-calibration-2026-09-25/install-delivered.log) retains delivery output. ARCHi reopened at Light & sound with KIN Original/Liminal retained and nothing sent. The [native observation](../output/reader-calibration-2026-09-25/native-observation.json) leaves report-viewer interaction pending: file selection was confirmed in accessibility state, but **Review report** remained disabled. No report-decoder failure was established.

That same installed increment contains padded KIN portraits and activity-colored gentle pulsing, preserving the original core and profile. The Light & sound cards and Warm rose Respond preview were observed with Qwen still reporting nothing sent. This is presentation evidence, not model calibration, an all-angle animation review or a complete accessibility pass.

The first calibration attempt against the installed Qwen3.5:9b GGUF failed in the pinned upstream loader before any activation was acquired: `qwen35.rope.dimension_sections` had three entries where four were expected. The [run-01 receipt](../output/reader-calibration-2026-09-25/run-01/acquisition-receipt.json) records exit code 1 and zero generated tokens; the [loader log](../output/reader-calibration-2026-09-25/run-01/acquisition.log) retains the exact error. This is a compatibility failure, not a negative result for a fitted reader and not evidence that Qwen is missing.

The separately selected Qwen3:8b run completed all **24 prefills in 53.34 seconds**, using **3,082 input tokens**, with **1,953,107 bytes** of retained activation output and **zero generated tokens**. Its [acquisition receipt](../output/reader-calibration-2026-09-25/run-02/acquisition-receipt.json) records exit code 0, and the [activation output](../output/reader-calibration-2026-09-25/run-02/activations.json) records the actual input count. This demonstrates bounded real-weight residual extraction, not a measured answer or reader qualification.

The [fit report](../output/reader-calibration-2026-09-25/run-02/calibration-report.json) records **qualification-failed**: calibration separation **−0.526166**, and **4/8 holdout examples correct**. The frozen gate required positive calibration separation and signed margin at least `0.1` on every calibration and holdout example. No importable `reader.json` was emitted, no measurements were enabled, and no holdout-driven retry occurred. The eight holdout examples comprise four matched synthetic groups; this small result supplies no general-chat, truth-detection or population-error claim. Changing models creates a separate model-bound experiment, not an automatic fallback. Installing the workflow does not change this failed qualification.

## Boundaries implemented

- Read-only shadow mode; no activation writes, steering, or automatic development.
- Fixed bundled executable; imported files cannot select a command or executable path.
- Pinned source revision, source archive digest, native architecture, runtime hashes and license notices.
- Bounded reader, request, output, token count, deadline and stderr; owned process termination on Stop.
- Complete output and normal child exit required; token-limit partial replies are rejected.
- Exact prompt reconstruction and special-marker rejection prevent source text introducing ChatML delimiters. Inputs containing `<|` fail closed in this initial adapter.
- External providers and Compare are blocked while measurements are enabled; no automatic external fallback, including the store-owned timeout path. Ordinary routing remains available when measurements are off.
- No model/reader substitution on failure. Return to standard local Qwen explicitly to resume that route.

## What remains

No qualified reader is available or enabled. A future approved study needs its own revised hypothesis/protocol and a genuinely fresh holdout; this result must not be re-labelled through threshold changes or retries. A fabricated unit vector, completed acquisition or inherited test count cannot substitute for qualification. Report-viewer interaction, the Qwen3.5 loader mismatch, general-chat validity, measured-answer behavior, memory/latency suitability and any benefit to Hampton adaptation remain open at this checkpoint.

The broader numerical Q2E/coupling reference and R2 development contracts remain separately versioned research components. This runtime does not silently replace native Q2E pressures or install all inherited modules. Steering requires its own bounded integration and evidence before it can be enabled.

Build details and protocol: [GGUF worker](../research/representation/gguf/README.md). Delivery observations: `output/gguf-representation-build-2026-09-25/delivery-receipt.json` and the appended developer-ledger evidence manifest.
