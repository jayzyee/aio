#!/usr/bin/env python3
"""Compare Aio-L0 composition, a flat template, and optional local Qwen."""

from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any

from language_engine import AioLanguage, message_from_dict, surface_constraints


ROOT = Path(__file__).parent
QWEN_MODEL = "Qwen/Qwen2.5-0.5B-Instruct"


def _read_cases() -> list[dict[str, Any]]:
    path = ROOT / "benchmarks" / "language_cases.jsonl"
    return [json.loads(line) for line in path.read_text(encoding="utf-8").splitlines()]


def _naive_template(message: Any, language: AioLanguage) -> str:
    """Baseline: fill slots in one fixed order, omitting most grammar operators."""
    clause = message.clause
    subject = language._noun_phrase(clause.subject)
    if message.act == "request":
        body = language._predicate(clause, "base", include_negation=False)
        return f"Please {body}."
    verb = language._verb(clause.verb, "base")
    if clause.object:
        verb += f" {language._noun_phrase(clause.object)}"
    if clause.adverb:
        verb += f" {language.lexicon['adverbs'][clause.adverb]}"
    ending = "?" if message.act == "question" else "."
    return f"{subject} {verb}{ending}"


def _qwen_answer(
    model: Any,
    tokenizer: Any,
    frame: dict[str, Any],
    anchors: list[str],
) -> str:
    messages = [
        {
            "role": "system",
            "content": (
                "You are a sentence planner. Express the requested meaning in exactly "
                "one natural English sentence. Preserve who does what, tense, negation, "
                "modality, question/request form, and causal relations. Do not invent "
                "details. Use every listed anchor in the sentence. For act=question, "
                "write an interrogative sentence addressed to the reader; do not "
                "describe someone asking a question. For act=request, write an "
                "imperative addressed to the reader; do not describe a request. For "
                "act=assert, write a declarative sentence. Output only the sentence."
                "\n\nExamples:\n"
                "Frame: {\"act\":\"assert\",\"clause\":{\"subject\":{\"lemma\":\"bell\"},"
                "\"verb\":\"carry\",\"object\":{\"lemma\":\"crystal\"}}}\n"
                "Sentence: The bell carries a crystal.\n"
                "Frame: {\"act\":\"question\",\"clause\":{\"subject\":{\"lemma\":\"bell\"},"
                "\"verb\":\"carry\",\"object\":{\"lemma\":\"crystal\"}}}\n"
                "Sentence: Does the bell carry a crystal?\n"
                "Frame: {\"act\":\"request\",\"clause\":{\"subject\":{\"lemma\":\"traveler\"},"
                "\"verb\":\"carry\",\"object\":{\"lemma\":\"map\"}}}\n"
                "Sentence: Please carry the map."
            ),
        },
        {
            "role": "user",
            "content": (
                "Realize this meaning frame as one utterance. The `act` field says "
                "what kind of utterance to produce. `subject` performs `verb`; "
                "`object` receives it. `tense`, `negative`, `modality`, and "
                "`question_word` must be expressed:\n"
                f"{json.dumps(frame, ensure_ascii=False)}\n"
                f"Required exact word forms: {', '.join(anchors)}."
            ),
        },
    ]
    prompt = tokenizer.apply_chat_template(
        messages, tokenize=False, add_generation_prompt=True
    )
    inputs = tokenizer(prompt, return_tensors="pt")
    outputs = model.generate(
        **inputs,
        max_new_tokens=64,
        do_sample=False,
        pad_token_id=tokenizer.eos_token_id,
    )
    generated = outputs[0, inputs["input_ids"].shape[1] :]
    return tokenizer.decode(generated, skip_special_tokens=True).strip()


def _score(
    answers: list[dict[str, Any]], expected_count: int, total_anchors: int
) -> dict[str, float]:
    return {
        "all_structural_constraints": round(
            sum(row["all_constraints"] for row in answers) / expected_count, 3
        ),
        "individual_constraint_rate": round(
            sum(
                sum(row["constraints"].values()) for row in answers
            )
            / sum(len(row["constraints"]) for row in answers),
            3,
        ),
        "required_anchor_recall": round(
            sum(row["anchor_hits"] for row in answers) / total_anchors, 3
        ),
        "mean_words": round(
            sum(row["word_count"] for row in answers) / expected_count, 1
        ),
    }


def run(include_qwen: bool = False) -> dict[str, Any]:
    language = AioLanguage()
    cases = _read_cases()
    models: dict[str, list[dict[str, Any]]] = {
        "Aio-L0 compositional speaker": [],
        "flat template baseline": [],
    }
    qwen_model = None
    qwen_tokenizer = None
    if include_qwen:
        try:
            import torch
            from transformers import AutoModelForCausalLM, AutoTokenizer
        except ImportError as error:
            raise RuntimeError(
                "Install gpt6mini/requirements-reference.txt to run Qwen."
            ) from error
        torch.set_num_threads(min(4, torch.get_num_threads()))
        qwen_tokenizer = AutoTokenizer.from_pretrained(QWEN_MODEL)
        qwen_model = AutoModelForCausalLM.from_pretrained(QWEN_MODEL)
        qwen_model.eval()
        models[QWEN_MODEL] = []

    for case in cases:
        message = message_from_dict(case["frame"])
        variants = {
            "Aio-L0 compositional speaker": language.speak(message),
            "flat template baseline": _naive_template(message, language),
        }
        if qwen_model is not None and qwen_tokenizer is not None:
            variants[QWEN_MODEL] = _qwen_answer(
                qwen_model,
                qwen_tokenizer,
                case["frame"],
                case["expected_anchors"],
            )

        for model_name, utterance in variants.items():
            constraints = surface_constraints(message, utterance, language)
            tokens = utterance.casefold().replace("?", "").replace(".", "").split()
            anchor_hits = sum(
                anchor.casefold() in tokens for anchor in case["expected_anchors"]
            )
            models[model_name].append(
                {
                    "id": case["id"],
                    "utterance": utterance,
                    "constraints": constraints,
                    "all_constraints": all(constraints.values()),
                    "anchor_hits": anchor_hits,
                    "word_count": len(tokens),
                }
            )

    total_anchors = sum(len(case["expected_anchors"]) for case in cases)
    return {
        "benchmark": "Aio-L0 compositional language smoke test",
        "case_count": len(cases),
        "lexicon_size": {
            category: len(entries) for category, entries in language.lexicon.items()
        },
        "models": {
            name: {
                "scores": _score(rows, len(cases), total_anchors),
                "answers": rows,
            }
            for name, rows in models.items()
        },
        "interpretation": (
            "These automatic checks test only this small grammar's explicit "
            "features, required words, and exact canonical frame sequence. "
            "They do not measure naturalness, conversation quality, or general "
            "intelligence. Human fluency ratings are still required."
        ),
    }


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--qwen", action="store_true", help=f"run {QWEN_MODEL} locally")
    parser.add_argument("--output", type=Path, help="optional JSON report path")
    args = parser.parse_args()
    report = run(include_qwen=args.qwen)
    serialized = json.dumps(report, indent=2, ensure_ascii=False)
    if args.output:
        args.output.write_text(serialized + "\n", encoding="utf-8")
    print(serialized)


if __name__ == "__main__":
    main()
