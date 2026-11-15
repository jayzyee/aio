"""Aio-0: a source-grounded associative reasoning experiment.

This is deliberately not a transformer. It learns a sparse association graph
from the book's sentence traces, spreads query activation through that graph,
and only speaks from retrieved, attributed evidence.
"""

from __future__ import annotations

import json
import math
import re
from collections import Counter, defaultdict
from dataclasses import dataclass
from pathlib import Path
from typing import Any


DEFAULT_BOOKS = Path(__file__).parent / "knowledge" / "books.json"
TOKEN_PATTERN = re.compile(r"[a-z0-9]+")
SENTENCE_PATTERN = re.compile(r"(?<=[.!?])\s+")
STOP_WORDS = {
    "a", "an", "and", "are", "as", "at", "be", "been", "being", "but",
    "by", "did", "do", "does", "for", "from", "had", "has", "have", "he",
    "her", "here", "him", "his", "how", "i", "if", "in", "into", "is",
    "it", "its", "me", "my", "of", "on", "or", "our", "she", "that",
    "the", "their", "them", "there", "these", "they", "this", "those",
    "to", "us", "was", "we", "were", "what", "when", "where", "which",
    "who", "why", "will", "with", "you", "your",
}
IRREGULAR = {
    "leaves": "leaf",
    "went": "go",
    "better": "good",
    "worse": "bad",
    "moisture": "moist",
    "proves": "prove",
    "proven": "prove",
    "proof": "prove",
    "conclude": "infer",
    "concludes": "infer",
    "concluded": "infer",
    "inference": "infer",
    "inferences": "infer",
}
CAUSE_PATTERNS = (
    ({"dry"}, {"wilt"}, "Dry soil may have contributed to the wilting."),
    ({"loose"}, {"light", "lit"}, "A loose connection may have kept the lamp from lighting."),
    ({"blocked"}, {"flow", "move", "stop"}, "A blockage may have interrupted the process."),
    ({"broken"}, {"work", "function", "light"}, "The damage may have prevented it from working."),
    ({"empty"}, {"work", "function", "run"}, "The empty supply may have contributed to the failure."),
)
CAVEAT_MARKERS = (
    "not a controlled experiment",
    "do not describe a controlled experiment",
    "does not prove",
    "cannot prove",
    "not prove",
)


def _stem(token: str) -> str:
    if token in IRREGULAR:
        return IRREGULAR[token]
    if len(token) > 5 and token.endswith("ies"):
        return token[:-3] + "y"
    if len(token) > 5 and token.endswith("ing"):
        token = token[:-3]
        if len(token) > 2 and token[-1] == token[-2]:
            token = token[:-1]
        return token
    if len(token) > 4 and token.endswith("ed"):
        token = token[:-2]
        if len(token) > 2 and token[-1] == token[-2]:
            token = token[:-1]
        return token
    if len(token) > 4 and token.endswith("es"):
        return token[:-2]
    if len(token) > 3 and token.endswith("s"):
        return token[:-1]
    return token


def _terms(text: str) -> list[str]:
    return [
        _stem(token)
        for token in TOKEN_PATTERN.findall(text.casefold())
        if token not in STOP_WORDS
    ]


@dataclass(frozen=True)
class Trace:
    trace_id: str
    source_id: str
    source_title: str
    section_id: str
    section_title: str
    text: str
    vector: dict[str, float]
    norm: float


class AioMind:
    """Train an evidence memory from books and answer with source attribution."""

    def __init__(self, books_path: str | Path = DEFAULT_BOOKS) -> None:
        self.books_path = Path(books_path)
        self.traces: list[Trace] = []
        self.idf: dict[str, float] = {}
        self.associations: list[list[tuple[int, float]]] = []
        self._train()

    def _train(self) -> None:
        with self.books_path.open(encoding="utf-8") as book_file:
            data: dict[str, Any] = json.load(book_file)

        raw_traces: list[dict[str, str]] = []
        for book in data["books"]:
            for section in book["sections"]:
                sentences = SENTENCE_PATTERN.split(section["text"].strip())
                for sentence_index, sentence in enumerate(sentences):
                    sentence = sentence.strip()
                    if sentence:
                        raw_traces.append(
                            {
                                "trace_id": f"{book['id']}:{section['id']}:{sentence_index}",
                                "source_id": book["id"],
                                "source_title": book["title"],
                                "section_id": section["id"],
                                "section_title": section["title"],
                                "text": sentence,
                            }
                        )

        if not raw_traces:
            raise ValueError(f"No readable passages found in {self.books_path}")

        tokenized = [_terms(item["text"]) for item in raw_traces]
        document_frequency: Counter[str] = Counter()
        for tokens in tokenized:
            document_frequency.update(set(tokens))
        trace_count = len(raw_traces)
        self.idf = {
            token: math.log(1 + trace_count / (1 + frequency)) + 1
            for token, frequency in document_frequency.items()
        }

        for raw, tokens in zip(raw_traces, tokenized):
            term_frequency = Counter(tokens)
            vector = {
                token: (1 + math.log(count)) * self.idf[token]
                for token, count in term_frequency.items()
            }
            norm = math.sqrt(sum(weight * weight for weight in vector.values()))
            self.traces.append(Trace(**raw, vector=vector, norm=norm))

        self.associations = self._learn_associations()

    def _learn_associations(self) -> list[list[tuple[int, float]]]:
        """Learn a sparse Hebbian trace graph from shared book concepts."""
        postings: dict[str, list[int]] = defaultdict(list)
        for trace_index, trace in enumerate(self.traces):
            for token in trace.vector:
                postings[token].append(trace_index)

        shared_mass: dict[tuple[int, int], float] = defaultdict(float)
        for token, indexes in postings.items():
            contribution = self.idf[token] ** 2
            for offset, left in enumerate(indexes):
                for right in indexes[offset + 1 :]:
                    shared_mass[(left, right)] += contribution
        section_members: dict[tuple[str, str], list[int]] = defaultdict(list)
        for index, trace in enumerate(self.traces):
            section_members[(trace.source_id, trace.section_id)].append(index)
        for indexes in section_members.values():
            for offset, left in enumerate(indexes):
                for right in indexes[offset + 1 :]:
                    shared_mass[(left, right)] += (
                        0.35 * self.traces[left].norm * self.traces[right].norm
                    )

        rows: list[list[tuple[int, float]]] = [[] for _ in self.traces]
        for (left, right), mass in shared_mass.items():
            similarity = mass / (self.traces[left].norm * self.traces[right].norm)
            if similarity > 0:
                rows[left].append((right, similarity))
                rows[right].append((left, similarity))

        normalized: list[list[tuple[int, float]]] = []
        for neighbors in rows:
            total = sum(weight for _, weight in neighbors)
            normalized.append(
                [(index, weight / total) for index, weight in neighbors]
                if total
                else []
            )
        return normalized

    def _direct_activation(self, question: str) -> list[float]:
        query_counts = Counter(_terms(question))
        if not query_counts:
            return [0.0] * len(self.traces)
        query_vector = {
            token: (1 + math.log(count)) * self.idf.get(token, 0.0)
            for token, count in query_counts.items()
            if token in self.idf
        }
        query_norm = math.sqrt(sum(weight * weight for weight in query_vector.values()))
        if query_norm == 0:
            return [0.0] * len(self.traces)

        query_weight = sum(query_vector.values())
        return [
            sum(
                weight
                for token, weight in query_vector.items()
                if token in trace.vector
            )
            / query_weight
            if query_weight
            else 0.0
            for trace in self.traces
        ]

    def _resonate(self, direct: list[float]) -> list[float]:
        """Keep query evidence active while allowing two rounds of context spread."""
        activation = direct[:]
        for _ in range(2):
            context = [
                sum(weight * activation[index] for index, weight in neighbors)
                for neighbors in self.associations
            ]
            activation = [
                0.78 * direct[index] + 0.22 * context[index]
                for index in range(len(direct))
            ]
        return activation

    def retrieve(self, question: str, limit: int = 4) -> list[dict[str, Any]]:
        if limit < 1:
            raise ValueError("limit must be at least 1")
        direct = self._direct_activation(question)
        if not direct or max(direct) < 0.12:
            return []
        activation = self._resonate(direct)
        ranked = sorted(
            (
                index
                for index in range(len(self.traces))
                if direct[index] >= 0.04
            ),
            key=lambda index: (direct[index], activation[index]),
            reverse=True,
        )
        selected = ranked[:limit]
        if selected and len(selected) < limit:
            direct_neighbors = {
                index: max(
                    (
                        weight
                        for seed in ranked[:limit]
                        for neighbor, weight in self.associations[seed]
                        if neighbor == index
                    ),
                    default=0.0,
                )
                for index in range(len(self.traces))
            }
            selected_sections = {
                (self.traces[index].source_id, self.traces[index].section_id)
                for index in selected
            }
            contextual = sorted(
                (
                    index
                    for index, trace in enumerate(self.traces)
                    if index not in selected
                    and (trace.source_id, trace.section_id) in selected_sections
                    and activation[index] >= 0.025
                ),
                key=lambda index: (direct_neighbors[index], activation[index]),
                reverse=True,
            )
            selected.extend(contextual[: limit - len(selected)])
        selected_sections = {
            (self.traces[index].source_id, self.traces[index].section_id)
            for index in selected
        }

        # Keep a source's explicit uncertainty note attached to the evidence it qualifies.
        for index, trace in enumerate(self.traces):
            if (
                (trace.source_id, trace.section_id) in selected_sections
                and any(marker in trace.text.casefold() for marker in CAVEAT_MARKERS)
                and index not in selected
            ):
                selected.append(index)

        return [
            {
                "source_id": self.traces[index].source_id,
                "source_title": self.traces[index].source_title,
                "section_id": self.traces[index].section_id,
                "section_title": self.traces[index].section_title,
                "text": self.traces[index].text,
                "direct_match": round(direct[index], 4),
                "resonance": round(activation[index], 4),
            }
            for index in selected
        ]

    def answer(self, question: str) -> dict[str, Any]:
        evidence = self.retrieve(question)
        if not evidence:
            return {
                "question": question,
                "answer": "I couldn't find a passage in this book that supports an answer to that question.",
                "abstained": True,
                "support_level": "none",
                "evidence": [],
                "layers": ["no source resonance", "abstain"],
            }

        answer = self._realize(question, evidence)
        best_match = max(item["direct_match"] for item in evidence)
        support_level = "strong" if best_match >= 0.42 else "limited"
        return {
            "question": question,
            "answer": answer,
            "abstained": False,
            "support_level": support_level,
            "evidence": evidence,
            "layers": [
                "sparse book encoding",
                "Hebbian concept association",
                "iterative resonance",
                "evidence and uncertainty audit",
                "source-constrained realization",
            ],
        }

    def _realize(self, question: str, evidence: list[dict[str, Any]]) -> str:
        unique_sentences: list[str] = []
        summary_items: list[dict[str, Any]] = []
        seen: set[str] = set()
        for item in evidence:
            text = item["text"]
            if text not in seen and not any(
                marker in text.casefold() for marker in CAVEAT_MARKERS
            ):
                unique_sentences.append(text)
                summary_items.append(item)
                seen.add(text)
            if len(unique_sentences) == 2:
                break

        if not unique_sentences:
            unique_sentences = [evidence[0]["text"]]
            summary_items = [evidence[0]]
        summary = " ".join(unique_sentences)

        def citation_for(items: list[dict[str, Any]]) -> str:
            sources = dict.fromkeys(
                (item["source_title"], item["section_title"]) for item in items
            )
            citations = "; ".join(
                f"{title}, “{section}”" for title, section in sources
            )
            return f"({citations})"

        summary_citation = citation_for(summary_items)
        normalized_question = question.casefold()
        proof_words = any(
            phrase in normalized_question for phrase in ("prove", "proof", "establish")
        )
        asks_proof = (
            proof_words
            and normalized_question.lstrip().startswith(
                ("do ", "does ", "did ", "is ", "are ", "can ", "could ", "was ", "were ")
            )
        ) or "only cause" in normalized_question
        epistemic_why = (
            normalized_question.lstrip().startswith("why ")
            and any(word in normalized_question for word in ("pattern", "observation"))
            and proof_words
        )
        asks_cause = (
            normalized_question.lstrip().startswith("why ")
            and not asks_proof
            and not epistemic_why
        ) or any(
            phrase in normalized_question
            for phrase in ("what caused", "what was the cause", "what is the cause")
        )
        asks_interpretation = any(
            phrase in normalized_question
            for phrase in ("tell us", "role of", "what suggests", "what does")
        )
        if asks_proof and not asks_cause:
            caveat_item = next(
                (
                    item
                    for item in evidence
                    if any(marker in item["text"].casefold() for marker in CAVEAT_MARKERS)
                ),
                None,
            )
            if caveat_item:
                return (
                    "No. The observations do not prove the explanation was the only "
                    f"cause. The source says: “{caveat_item['text']}” "
                    f"{citation_for([caveat_item])}"
                )
            return f"The passages do not establish that conclusion. {summary} {summary_citation}"

        evidence_terms = set(_terms(" ".join(item["text"] for item in evidence)))
        if (
            asks_interpretation
            and {"moist", "leaf"}.issubset(evidence_terms)
            and {"wilt", "upright"}.issubset(evidence_terms)
        ):
            caveat_item = next(
                (
                    item
                    for item in evidence
                    if any(marker in item["text"].casefold() for marker in CAVEAT_MARKERS)
                ),
                None,
            )
            interpretation = (
                "This contrast is consistent with soil moisture being relevant to leaf "
                "condition, but it does not show that moisture was the only factor."
            )
            if caveat_item:
                return (
                    f"{summary} {interpretation} The source cautions: "
                    f"“{caveat_item['text']}” "
                    f"{citation_for(summary_items + [caveat_item])}"
                )
            return f"{summary} {interpretation} {summary_citation}"

        if asks_cause:
            all_evidence = " ".join(item["text"].casefold() for item in evidence)
            question_terms = set(_terms(question))
            hypothesis = next(
                (
                    explanation
                    for conditions, outcomes, explanation in CAUSE_PATTERNS
                    if conditions.intersection(set(_terms(all_evidence)))
                    and outcomes.intersection(question_terms)
                ),
                "The pattern is consistent with a possible explanation, but it does not establish cause by itself.",
            )
            caveat_item = next(
                (
                    item
                    for item in evidence
                    if any(marker in item["text"].casefold() for marker in CAVEAT_MARKERS)
                ),
                None,
            )
            if caveat_item:
                return (
                    f"{summary} {hypothesis} The source also cautions: "
                    f"“{caveat_item['text']}” "
                    f"{citation_for(summary_items + [caveat_item])}"
                )
            return f"{summary} {hypothesis} {summary_citation}"

        return f"The book reports: {summary} {summary_citation}"


def main() -> None:
    import argparse

    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("question", help="question to answer from the knowledge book")
    parser.add_argument("--books", type=Path, default=DEFAULT_BOOKS)
    args = parser.parse_args()
    print(json.dumps(AioMind(args.books).answer(args.question), indent=2, ensure_ascii=False))


if __name__ == "__main__":
    main()
