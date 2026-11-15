#!/usr/bin/env python3
"""Compare Aio-0 with lexical retrieval and an optional local Qwen model."""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Any

ROOT = Path(__file__).parent
sys.path.insert(0, str(ROOT / "tools"))

from aio_mind import AioMind  # noqa: E402
from search_knowledge import search_knowledge  # noqa: E402


QWEN_MODEL = "Qwen/Qwen2.5-0.5B-Instruct"
ABSTENTION_MARKERS = (
    "not in the source",
    "does not state",
    "doesn't state",
    "not provide",
    "can't verify",
    "cannot verify",
    "not enough information",
    "no relevant passage",
    "not mentioned",
)


def _read_jsonl(path: Path) -> list[dict[str, Any]]:
    return [json.loads(line) for line in path.read_text(encoding="utf-8").splitlines()]


def _is_abstention(answer: str) -> bool:
    lowered = answer.casefold()
    return any(marker in lowered for marker in ABSTENTION_MARKERS)


def _anchor_coverage(answer: str, expected_terms: list[str]) -> bool:
    lowered = answer.casefold()
    return all(term.casefold() in lowered for term in expected_terms)


def _qwen_answer(model: Any, tokenizer: Any, context: str, question: str) -> str:
    messages = [
        {
            "role": "system",
            "content": (
                "Answer as a careful reader using only the supplied book passages. "
                "Cite the passage title. If the passages do not answer the question, "
                "say so instead of using outside knowledge. Be concise and fluent."
            ),
        },
        {
            "role": "user",
            "content": f"BOOK PASSAGES\n{context}\n\nQUESTION\n{question}",
        },
    ]
    prompt = tokenizer.apply_chat_template(
        messages, tokenize=False, add_generation_prompt=True
    )
    inputs = tokenizer(prompt, return_tensors="pt")
    outputs = model.generate(
        **inputs,
        max_new_tokens=112,
        do_sample=False,
        pad_token_id=tokenizer.eos_token_id,
    )
    answer_tokens = outputs[0, inputs["input_ids"].shape[1] :]
    return tokenizer.decode(answer_tokens, skip_special_tokens=True).strip()


def _metrics(results: list[dict[str, Any]], expected_count: int) -> dict[str, float]:
    if not results:
        return {}
    anchored_rows = [row for row in results if row["expected_terms"]]
    answerable_rows = [row for row in results if row["expected_answerable"]]
    return {
        "answerability_accuracy": round(
            sum(row["answerability_correct"] for row in results) / expected_count, 3
        ),
        "evidence_anchor_coverage": round(
            sum(row["anchor_coverage"] for row in anchored_rows) / len(anchored_rows), 3
        ),
        "citation_or_retrieval_coverage": round(
            sum(row["evidence_covered"] for row in answerable_rows)
            / len(answerable_rows),
            3,
        ),
        "grounded_task_proxy": round(
            sum(
                row["answerability_correct"]
                and (
                    not row["expected_answerable"]
                    or (row["anchor_coverage"] and row["evidence_covered"])
                )
                for row in results
            )
            / expected_count,
            3,
        ),
    }


def run(include_qwen: bool = False) -> dict[str, Any]:
    cases = _read_jsonl(ROOT / "benchmarks" / "cases.jsonl")
    mind = AioMind()
    books = json.loads((ROOT / "knowledge" / "books.json").read_text(encoding="utf-8"))
    section_titles = {
        section["id"]: section["title"]
        for book in books["books"]
        for section in book["sections"]
    }
    qwen_model = None
    qwen_tokenizer = None
    context = ""
    if include_qwen:
        try:
            import torch
            from transformers import AutoModelForCausalLM, AutoTokenizer
        except ImportError as error:
            raise RuntimeError(
                "Qwen comparison dependencies are missing; install "
                "gpt6mini/requirements-reference.txt"
            ) from error

        torch.set_num_threads(min(4, torch.get_num_threads()))
        qwen_tokenizer = AutoTokenizer.from_pretrained(QWEN_MODEL)
        qwen_model = AutoModelForCausalLM.from_pretrained(QWEN_MODEL)
        qwen_model.eval()
        context = "\n\n".join(
            f"[{book['title']} / {section['title']}]\n{section['text']}"
            for book in books["books"]
            for section in book["sections"]
        )

    output: dict[str, Any] = {
        "benchmark": "Aio-0 source-grounded reasoning smoke test",
        "cases": len(cases),
        "reference_model": QWEN_MODEL if include_qwen else None,
        "models": {},
        "fluency_note": (
            "Fluency is shown in the answer samples for human inspection; "
            "these small tests do not provide a validated fluency score."
        ),
    }
    aio_rows: list[dict[str, Any]] = []
    lexical_rows: list[dict[str, Any]] = []
    qwen_rows: list[dict[str, Any]] = []

    for case in cases:
        question = case["question"]
        expected_answerable = case["expected_answerable"]
        expected_section = case["expected_section"]
        expected_terms = case["expected_terms"]

        aio_result = mind.answer(question)
        aio_answer = aio_result["answer"]
        aio_rows.append(
            {
                "question": question,
                "answer": aio_answer,
                "abstained": aio_result["abstained"],
                "answerability_correct": aio_result["abstained"] != expected_answerable,
                "anchor_coverage": _anchor_coverage(aio_answer, expected_terms),
                "expected_answerable": expected_answerable,
                "expected_terms": expected_terms,
                "evidence_covered": expected_section
                in {item["section_id"] for item in aio_result["evidence"]}
                if expected_answerable
                else aio_result["abstained"],
            }
        )

        lexical_results = search_knowledge(question, limit=3)
        lexical_rows.append(
            {
                "question": question,
                "answer": (
                    "Found source passages; no reasoning or answer generation is implemented."
                    if lexical_results
                    else "No matching passage found."
                ),
                "abstained": not bool(lexical_results),
                "answerability_correct": bool(lexical_results) == expected_answerable,
                "anchor_coverage": False,
                "expected_answerable": expected_answerable,
                "expected_terms": expected_terms,
                "evidence_covered": expected_section
                in {item["section_id"] for item in lexical_results}
                if expected_answerable
                else not lexical_results,
            }
        )

        if qwen_model is not None and qwen_tokenizer is not None:
            qwen_answer = _qwen_answer(qwen_model, qwen_tokenizer, context, question)
            qwen_abstained = _is_abstention(qwen_answer)
            qwen_rows.append(
                {
                    "question": question,
                    "answer": qwen_answer,
                    "abstained": qwen_abstained,
                    "answerability_correct": qwen_abstained != expected_answerable,
                    "anchor_coverage": _anchor_coverage(qwen_answer, expected_terms),
                    "expected_answerable": expected_answerable,
                    "expected_terms": expected_terms,
                    "evidence_covered": (
                        section_titles.get(expected_section, "").casefold()
                        in qwen_answer.casefold()
                    )
                    if expected_answerable
                    else qwen_abstained,
                }
            )

    output["models"]["Aio-0"] = {
        "metrics": _metrics(aio_rows, len(cases)),
        "answers": aio_rows,
    }
    output["models"]["lexical baseline"] = {
        "metrics": _metrics(lexical_rows, len(cases)),
        "answers": lexical_rows,
    }
    if include_qwen:
        output["models"][QWEN_MODEL] = {
            "metrics": _metrics(qwen_rows, len(cases)),
            "answers": qwen_rows,
        }
    return output


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--qwen",
        action="store_true",
        help=f"download/run {QWEN_MODEL} locally for a reference comparison",
    )
    parser.add_argument("--output", type=Path, help="optional JSON report path")
    args = parser.parse_args()
    report = run(include_qwen=args.qwen)
    serialized = json.dumps(report, indent=2, ensure_ascii=False)
    if args.output:
        args.output.write_text(serialized + "\n", encoding="utf-8")
    print(serialized)


if __name__ == "__main__":
    main()
