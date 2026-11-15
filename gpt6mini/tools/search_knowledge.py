#!/usr/bin/env python3
"""Search Aio GPT6 Mini's source-labelled knowledge passages."""

import argparse
import json
import re
from pathlib import Path
from typing import Any


KNOWLEDGE_PATH = Path(__file__).resolve().parents[1] / "knowledge" / "books.json"
TOKEN_PATTERN = re.compile(r"[a-z0-9]+")
STOP_WORDS = {
    "a",
    "an",
    "and",
    "are",
    "by",
    "did",
    "do",
    "does",
    "for",
    "from",
    "how",
    "i",
    "in",
    "is",
    "it",
    "of",
    "on",
    "or",
    "the",
    "this",
    "to",
    "was",
    "were",
    "what",
    "when",
    "where",
    "which",
    "who",
    "why",
    "with",
}


def _tokens(text: str) -> set[str]:
    return {
        token
        for token in TOKEN_PATTERN.findall(text.casefold())
        if token not in STOP_WORDS
    }


def search_knowledge(query: str, limit: int = 3) -> list[dict[str, str]]:
    """Return up to ``limit`` source passages that share terms with ``query``."""
    if limit < 1:
        raise ValueError("limit must be at least 1")

    query_tokens = _tokens(query)
    if not query_tokens:
        return []

    with KNOWLEDGE_PATH.open(encoding="utf-8") as knowledge_file:
        data: dict[str, Any] = json.load(knowledge_file)

    matches: list[tuple[int, int, dict[str, str]]] = []
    position = 0
    for book in data["books"]:
        for section in book["sections"]:
            text = section["text"]
            overlap = len(query_tokens & _tokens(text))
            if overlap:
                matches.append(
                    (
                        overlap,
                        position,
                        {
                            "source_id": book["id"],
                            "source_title": book["title"],
                            "section_id": section["id"],
                            "section_title": section["title"],
                            "text": text,
                        },
                    )
                )
            position += 1

    matches.sort(key=lambda match: (-match[0], match[1]))
    return [result for _, _, result in matches[:limit]]


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("query", help="words or question to search for")
    parser.add_argument("--limit", type=int, default=3, help="maximum results")
    args = parser.parse_args()
    if args.limit < 1:
        parser.error("--limit must be at least 1")

    output = {"query": args.query, "results": search_knowledge(args.query, args.limit)}
    print(json.dumps(output, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
