#!/usr/bin/env python3
"""Prepare, acquire and fit one bounded synthetic-record reader; no cloud calls.

Each stage has a separate explicit command. Qualification failure produces a
report, never an importable reader. No held-out-driven retry or search exists.
"""
from __future__ import annotations

import argparse
from collections import Counter
import hashlib
import json
import math
from pathlib import Path
import re
import subprocess
import sys
import time
import uuid

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[2]
SCOPE = "synthetic-record-field-support/prompt-final/v1"
BACKEND = "llama.cpp:161755f29"
TEMPLATE = ("<|im_start|>system\n{{system}}<|im_end|>\n<|im_start|>user\n{{input}}"
            "\n\nReturn exactly one JSON object matching this schema:\n{{schema}}"
            "<|im_end|>\n<|im_start|>assistant\n<think>\n\n</think>\n\n")


def encoded(value):
    return json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False, allow_nan=False)


def sha(value):
    return hashlib.sha256(value if isinstance(value, bytes) else value.encode()).hexdigest()


def save(path, value):
    with path.open("x", encoding="utf-8") as stream:
        stream.write(encoded(value) + "\n")


def read(path, limit=16 * 1024 * 1024):
    if path.is_symlink() or not path.is_file() or path.stat().st_size > limit:
        raise ValueError("Expected a bounded regular file: " + str(path))
    return json.loads(path.read_text(), parse_constant=lambda _: (_ for _ in ()).throw(ValueError("Nonfinite JSON")))


def prepare(output, model_name):
    output.mkdir(parents=True, exist_ok=False)
    model_root = Path.home() / ".ollama/models"
    family, tag = model_name.split(":")
    manifest_path = model_root / "manifests/registry.ollama.ai/library" / family / tag
    manifest = read(manifest_path, 256 * 1024)
    model_layers = [v for v in manifest["layers"] if v["mediaType"] == "application/vnd.ollama.image.model"]
    if len(model_layers) != 1:
        raise ValueError("Expected exactly one installed GGUF blob")
    blob_digest = model_layers[0]["digest"].removeprefix("sha256:")
    if not re.fullmatch(r"[a-f0-9]{64}", blob_digest):
        raise ValueError("Invalid installed model digest")
    groups = [
        ("fit", "parcel", "PX-41", "PX-87", "destination", "weight", "Harbor", "nine", "Which destination is listed for {id}?"),
        ("fit", "greenhouse", "GH-52", "GH-93", "species", "shelf", "Basil", "upper", "Read the species field for {id}."),
        ("fit", "equipment", "EQ-24", "EQ-68", "voltage", "owner", "twelve", "Mira", "What voltage belongs to {id}?"),
        ("fit", "storage", "BN-35", "BN-79", "contents", "seal", "Ribbon", "blue", "Find the contents recorded under {id}."),
        ("calibration", "train", "TR-16", "TR-82", "platform", "route", "four", "Coastal", "Give the platform entry for {id}."),
        ("calibration", "parts", "PT-27", "PT-64", "material", "batch", "Brass", "winter", "Look up {id} and report its material."),
        ("calibration", "museum", "MU-38", "MU-75", "gallery", "condition", "East", "sealed", "Locate {id}: which gallery does its record name?"),
        ("calibration", "recipe", "RC-49", "RC-86", "temperature", "servings", "medium", "six", "Retrieve the temperature attributed to {id}."),
        ("holdout", "farm", "FM-53", "FM-97", "destination", "crate", "Orchard", "cedar", "Where is {id} scheduled for delivery? Return its destination field."),
        ("holdout", "audio", "AU-62", "AU-18", "instrument", "tempo", "Cello", "slow", "For track {id}, identify the instrument entry."),
        ("holdout", "library", "LB-73", "LB-29", "borrower", "edition", "Nora", "second", "Name the borrower attached to loan {id}."),
        ("holdout", "laboratory", "LA-84", "LA-31", "cabinet", "assay", "West", "salinity", "Consult the storage log: report {id}'s cabinet."),
    ]
    examples, samples = [], []
    schema = encoded({"type": "object", "properties": {"answer": {"type": "string"}},
                      "required": ["answer"], "additionalProperties": False})
    for index, (split, family, target, other, field, distractor, value, other_value, question) in enumerate(groups):
        system = (f"Read the supplied {family} records. Answer only the exact record and field asked for. "
                  "Use only those records. If that field is absent for that record, answer NEED_SOURCE. Return one JSON object.")
        pair = []
        for positive in ([True, False] if index % 2 == 0 else [False, True]):
            rows = [{"id": target if positive else other, "field": field, "value": value},
                    {"id": other if positive else target, "field": distractor, "value": other_value}]
            if index % 2:
                rows.reverse()
            # Different layouts are frozen by group; both pair members use the
            # same layout, question and exact word inventory.
            if index < 4:
                rendered = "\n".join(f"{r['id']}: {r['field']} = {r['value']}" for r in rows)
            elif index < 8:
                rendered = "record | field | value\n" + "\n".join(f"{r['id']} | {r['field']} | {r['value']}" for r in rows)
            else:
                rendered = "\n".join(f"Entry [{r['id']}] has {r['field']} '{r['value']}'." for r in rows)
            label = any(r["id"] == target and r["field"] == field and r["value"] for r in rows)
            assert bool(label) == positive
            sample_id = f"record-{index + 1:02d}-{len(pair) + 1}"
            input_text = encoded({"question": question.format(id=target), "source": rendered})
            prompt = ("<|im_start|>system\n" + system + "<|im_end|>\n<|im_start|>user\n" + input_text
                      + "\n\nReturn exactly one JSON object matching this schema:\n" + schema
                      + "<|im_end|>\n<|im_start|>assistant\n<think>\n\n</think>\n\n")
            sample = {"sample_id": sample_id, "input": input_text, "system": system, "response_schema": schema,
                      "prompt": prompt, "input_digest": sha(input_text), "system_digest": sha(system),
                      "schema_digest": sha(schema), "prompt_digest": sha(prompt)}
            pair.append(sample)
            samples.append(sample)
            examples.append({"sampleID": sample_id, "group": family, "split": split,
                             "label": 1 if positive else -1, "records": rows,
                             "query": {"id": target, "field": field}, "promptDigest": sha(prompt)})
        assert Counter(re.findall(r"\w+|[^\w\s]", pair[0]["prompt"])) == Counter(re.findall(r"\w+|[^\w\s]", pair[1]["prompt"]))
    dataset = {"schema": "archi-synthetic-record-dataset/v1", "scope": SCOPE, "syntheticOnly": True, "examples": examples}
    save(output / "dataset.json", dataset)
    plan = {"schema": "archi-reader-plan/v1", "algorithm": "mean_contrast_reader", "layer": "l_out-15",
            "tokenRule": "prompt-last", "measurementScope": SCOPE, "hiddenWidth": 4096,
            "fitPairs": 4, "calibrationPairs": 4, "holdoutPairs": 4, "minimumSignedMargin": 0.1,
            "requiresPerfectCalibrationSeparation": True, "requiresAllHoldoutCorrect": True,
            "layerSearch": False, "algorithmSearch": False, "heldoutRetries": False,
            "modelName": model_name, "modelDigest": sha(manifest_path.read_bytes()), "modelBlobDigest": blob_digest,
            "templateDigest": sha(TEMPLATE), "backendRevision": BACKEND,
            "datasetDigest": sha((output / "dataset.json").read_bytes()),
            "numericsSourceDigest": sha((HERE.parent / "archi_repe/numerics.py").read_bytes()),
            "workflowSourceDigest": sha(Path(__file__).read_bytes()),
            "limitation": "Twelve synthetic record-lookup groups, four held out. Not general chat or truth qualification."}
    save(output / "plan.json", plan)
    payload = encoded(samples)
    request = {"schema": "archi-gguf-calibration-request/v1", "run_id": str(uuid.uuid4()),
               "purpose": "synthetic-reader-calibration", "synthetic_only": True,
               "model_name": model_name, "model_digest": plan["modelDigest"], "model_blob_digest": blob_digest,
               "model_path": str(model_root / ("blobs/sha256-" + blob_digest)),
               "tokenizer_digest": blob_digest, "template_digest": sha(TEMPLATE), "backend_revision": BACKEND,
               "precision": "Q4_K_M", "layer": plan["layer"], "max_input_tokens": 512,
               "max_total_input_tokens": 8192, "deadline_ms": 540000, "samples": samples,
               "samples_payload": payload, "samples_payload_digest": sha(payload), "dataset_digest": plan["datasetDigest"]}
    save(output / "acquisition-request.json", request)
    print("Prepared 24 synthetic prefills: 8 fit, 8 calibration, 8 untouched holdout. No model loaded.", flush=True)


def acquire(output, worker):
    request = read(output / "acquisition-request.json", 1024 * 1024)
    plan = read(output / "plan.json")
    if sha((output / "dataset.json").read_bytes()) != plan["datasetDigest"]:
        raise ValueError("Prepared dataset changed")
    manifest = read(worker.parent / "build-manifest.json", 65536)
    if sha(worker.read_bytes()) != manifest["runtime_sha256"][worker.name]:
        raise ValueError("Worker hash mismatch")
    for name, expected in manifest["runtime_sha256"].items():
        if Path(name).name != name or sha((worker.parent / name).read_bytes()) != expected:
            raise ValueError("Runtime member changed")
    # One explicit acquisition per prepared output directory. Failed runs remain
    # attributable; creating a new run cannot preserve 'untouched' after review.
    save(output / "acquisition-start.json", {"requestDigest": sha((output / "acquisition-request.json").read_bytes()),
         "workerDigest": sha(worker.read_bytes()), "startedAtUnix": time.time()})
    stdout_path = output / "activations.json"
    with stdout_path.open("xb") as stdout, (output / "acquisition.log").open("xb") as stderr:
        child = subprocess.Popen([str(worker), "--acquire-calibration"], stdin=subprocess.PIPE,
                                 stdout=stdout, stderr=stderr, env={"PATH": "/usr/bin:/bin", "LANG": "en_US.UTF-8"})
        started = time.monotonic()
        try:
            child.communicate(encoded(request).encode(), timeout=550)
        except (subprocess.TimeoutExpired, KeyboardInterrupt):
            child.terminate()
            try:
                child.wait(timeout=2)
            except subprocess.TimeoutExpired:
                child.kill(); child.wait()
            raise
    receipt = {"exitCode": child.returncode, "elapsedSeconds": time.monotonic() - started,
               "activationBytes": stdout_path.stat().st_size, "activationDigest": sha(stdout_path.read_bytes()),
               "generatedTokens": 0, "inputBudget": 8192}
    save(output / "acquisition-receipt.json", receipt)
    if child.returncode:
        raise RuntimeError("Calibration acquisition failed; see acquisition.log and activations.json")
    print("Activation acquisition complete; no answers generated.", flush=True)


def fit(output):
    import numpy as np
    sys.path.insert(0, str(HERE.parent))
    from archi_repe.numerics import mean_contrast_reader, standardized_assay
    plan, dataset, observed, request = [read(output / name) for name in
        ("plan.json", "dataset.json", "activations.json", "acquisition-request.json")]
    start, receipt = [read(output / name) for name in ("acquisition-start.json", "acquisition-receipt.json")]
    if (receipt.get("exitCode") != 0
            or receipt.get("activationDigest") != sha((output / "activations.json").read_bytes())
            or start.get("requestDigest") != sha((output / "acquisition-request.json").read_bytes())):
        raise ValueError("Acquisition receipts do not bind a successful unchanged result")
    if (sha((output / "dataset.json").read_bytes()) != plan["datasetDigest"]
            or sha((HERE.parent / "archi_repe/numerics.py").read_bytes()) != plan["numericsSourceDigest"]
            or sha(Path(__file__).read_bytes()) != plan["workflowSourceDigest"]):
        raise ValueError("Frozen plan sources changed")
    if observed.get("schema") != "archi-gguf-calibration-result/v1" or observed.get("status") != "ok":
        raise ValueError("No successful calibration acquisition")
    if (observed.get("token_rule") != "prompt-last"
            or observed.get("context_policy") != "fresh-context-per-sample"
            or observed.get("generated_tokens") != 0
            or observed.get("hidden_width") != 4096 or observed.get("sample_count") != 24):
        raise ValueError("Acquisition did not preserve the prompt-only measurement contract")
    for key in ("run_id", "model_name", "model_digest", "model_blob_digest", "tokenizer_digest", "template_digest",
                "backend_revision", "precision", "layer", "samples_payload_digest", "dataset_digest"):
        if observed.get(key) != request[key]:
            raise ValueError("Acquisition identity mismatch: " + key)
    vectors = {}
    offered = {v["sample_id"]: v for v in request["samples"]}
    for sample in observed["samples"]:
        sid = sample["sample_id"]
        if sid not in offered or sid in vectors:
            raise ValueError("Unexpected/duplicate acquired sample")
        for key in ("prompt_digest", "input_digest", "system_digest", "schema_digest"):
            if sample[key] != offered[sid][key]:
                raise ValueError("Sample binding mismatch")
        if (type(sample.get("input_tokens")) is not int or not 1 <= sample["input_tokens"] <= 512
                or sample.get("token_position") != sample["input_tokens"] - 1
                or sample.get("layer") != plan["layer"]):
            raise ValueError("Sample was not acquired at the declared prompt-final position")
        vector = np.asarray(sample["activation"], dtype=np.float64)
        if vector.shape != (4096,) or not np.isfinite(vector).all():
            raise ValueError("Invalid acquired residual")
        vectors[sid] = vector
    if set(vectors) != set(offered) or len(vectors) != 24:
        raise ValueError("Incomplete acquisition")
    total_tokens = sum(x["input_tokens"] for x in observed["samples"])
    if total_tokens > 8192 or observed.get("total_input_tokens") != total_tokens:
        raise ValueError("Acquisition token accounting mismatch")
    examples = dataset["examples"]
    partitions = {s: [v for v in examples if v["split"] == s] for s in ("fit", "calibration", "holdout")}
    positive = [vectors[x["sampleID"]] for x in partitions["fit"] if x["label"] == 1]
    negative = [vectors[x["sampleID"]] for x in partitions["fit"] if x["label"] == -1]
    fitted = mean_contrast_reader(positive, negative)
    if not fitted.available:
        raise ValueError("Fitted reader unavailable: " + str(fitted.reason))
    direction = fitted.direction
    center = np.mean([vectors[x["sampleID"]] for x in partitions["fit"]], axis=0)
    def scores(split):
        return [float(direction @ (vectors[x["sampleID"]] - center)) for x in partitions[split]]
    calibration = scores("calibration")
    positive_cal = [s for x, s in zip(partitions["calibration"], calibration) if x["label"] == 1]
    negative_cal = [s for x, s in zip(partitions["calibration"], calibration) if x["label"] == -1]
    separation = min(positive_cal) - max(negative_cal)
    offset = (min(positive_cal) + max(negative_cal)) / 2
    scale = float(np.std(calibration))
    if not math.isfinite(scale) or scale <= 1e-12:
        raise ValueError("Calibration scale is unavailable")
    numeric = {"directions": [direction.tolist()], "center": center.tolist(), "scoreOffset": [offset], "scoreScale": [scale]}
    # Freeze every parameter before inspecting holdout labels/scores.
    save(output / "frozen-fit.json", {"algorithm": plan["algorithm"], "numeric": numeric,
                                     "planDigest": sha((output / "plan.json").read_bytes())})
    results = []
    for split in ("calibration", "holdout"):
        for example in partitions[split]:
            assay = standardized_assay(vectors[example["sampleID"]], direction, center,
                                       score_mean=offset, score_scale=scale)
            if not assay.available:
                raise ValueError("Assay unavailable")
            signed = example["label"] * assay.standardized_score
            results.append({"sampleID": example["sampleID"], "group": example["group"], "split": split,
                            "label": example["label"], "rawScore": assay.raw_score,
                            "coordinate": assay.bounded_score, "signedMargin": signed,
                            "correct": signed > 0, "marginPass": signed >= plan["minimumSignedMargin"]})
    holdout = [x for x in results if x["split"] == "holdout"]
    passed = separation > 0 and all(x["marginPass"] for x in results)
    report = {"schema": "archi-gguf-reader-calibration/v1", "status": "limited-shadow-pass" if passed else "qualification-failed",
              "measurementScope": SCOPE, "tokenRule": "prompt-last", "fitCount": 8, "calibrationCount": 8,
              "holdoutCount": 8, "holdoutCorrect": sum(x["correct"] for x in holdout),
              "holdoutAccuracy": sum(x["correct"] for x in holdout) / 8,
              "plan": plan, "planDigest": sha((output / "plan.json").read_bytes()),
              "activationDigest": sha((output / "activations.json").read_bytes()),
              "acquisitionReceiptDigest": sha((output / "acquisition-receipt.json").read_bytes()),
              "acquisitionStartDigest": sha((output / "acquisition-start.json").read_bytes()),
              "frozenFitDigest": sha((output / "frozen-fit.json").read_bytes()),
              "calibrationSeparation": separation, "minimumSignedMargin": 0.1, "results": results,
              "limitations": ["Four held-out synthetic lookup groups; no population error guarantee.",
                              "Not calibrated for ordinary ARCHi chat prompts, generated-token states, truth, or authority.",
                              "No weight training, activation steering or response-quality comparison."]}
    report_text = encoded(report)
    save(output / "calibration-report.json", report)
    if passed:
        reader = {"schemaVersion": "archi-gguf-reader/v2", "modelName": plan["modelName"],
                  "modelDigest": plan["modelDigest"], "modelBlobDigest": plan["modelBlobDigest"],
                  "namespace": "hampton.experimental.synthetic-record-field-support.v1",
                  "tokenizerDigest": plan["modelBlobDigest"], "templateDigest": plan["templateDigest"],
                  "backendRevision": BACKEND, "precision": "Q4_K_M", "layer": plan["layer"],
                  "readerName": "synthetic-record-field-support", "basisDigest": sha(encoded({"plan": plan, "numeric": numeric})),
                  "readerDigest": sha(encoded(numeric)), "calibrationDigest": sha(report_text),
                  "tokenRule": "prompt-last", "measurementScope": SCOPE, "calibrationReport": report_text,
                  "provenance": "Locally fitted from synthetic, paired record-lookup examples. Limited prefill-only qualification; not general truth or chat qualification.", **numeric}
        save(output / "reader.json", reader)
    print(encoded({"status": report["status"], "holdoutCorrect": report["holdoutCorrect"],
                   "holdoutCount": 8, "readerProduced": passed}), flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("stage", choices=["prepare", "acquire", "fit"])
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--worker", type=Path)
    parser.add_argument("--model", choices=["qwen3:8b", "qwen3.5:9b"], default="qwen3:8b")
    args = parser.parse_args()
    output = args.output.resolve()
    if not output.is_relative_to(REPO / "output"):
        raise ValueError("Keep calibration artifacts inside this checkout's ignored output/ directory")
    if args.stage == "prepare":
        prepare(output, args.model)
    elif args.stage == "acquire":
        if not args.worker:
            raise ValueError("Choose the explicitly built local worker")
        acquire(output, args.worker.resolve())
    else:
        fit(output)


if __name__ == "__main__":
    main()
