"""Aio-L0: a compositional English speaker over explicit meaning frames.

The syntax rules are hand-specified; the lexicon is loaded as data. This
prototype tests whether factorized meaning can generalize across combinations
without learning a next-token language model.
"""

from __future__ import annotations

import json
import re
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any


DEFAULT_LEXICON = Path(__file__).parent / "language_lexicon.json"
TOKEN_PATTERN = re.compile(r"[a-z]+")


@dataclass(frozen=True)
class Entity:
    lemma: str
    number: str = "singular"
    determiner: str = "the"
    adjectives: tuple[str, ...] = ()
    proper: bool = False
    pronoun: str | None = None


@dataclass(frozen=True)
class Clause:
    subject: Entity
    verb: str
    object: Entity | None = None
    tense: str = "present"
    negative: bool = False
    adverb: str | None = None


@dataclass(frozen=True)
class Message:
    act: str
    clause: Clause
    modality: str | None = None
    cause: Clause | None = None
    question_word: str | None = None


@dataclass
class DiscourseState:
    """Tiny context state used for reference and repair decisions."""

    last_subject: Entity | None = None
    turn_count: int = 0
    unresolved_referent: bool = False

    def observe(self, clause: Clause) -> None:
        self.last_subject = clause.subject
        self.turn_count += 1
        self.unresolved_referent = False

    def can_pronominalize(self, entity: Entity) -> bool:
        return (
            self.turn_count > 0
            and self.last_subject == entity
            and not self.unresolved_referent
        )


class AioLanguage:
    """Realize explicit messages using compositional syntax and a small lexicon."""

    def __init__(self, lexicon_path: str | Path = DEFAULT_LEXICON) -> None:
        with Path(lexicon_path).open(encoding="utf-8") as lexicon_file:
            self.lexicon: dict[str, dict[str, Any]] = json.load(lexicon_file)

    def speak(
        self,
        message: Message,
        state: DiscourseState | None = None,
        *,
        use_pronoun: bool = False,
    ) -> str:
        self._validate(message)
        discourse = state if state is not None else DiscourseState()
        subject = self._noun_phrase(
            message.clause.subject,
            pronominalize=use_pronoun
            and discourse.can_pronominalize(message.clause.subject),
        )
        clause = message.clause
        act = message.act

        if act == "request":
            if clause.negative or message.modality:
                raise ValueError("requests require a positive, non-modal clause")
            sentence = f"Please {self._predicate(clause, 'base', include_negation=False)}."
        elif act == "question":
            sentence = self._question(message)
        elif act == "assert":
            grammatical_number = self._number_in_context(
                clause.subject,
                pronominalize=use_pronoun
                and discourse.can_pronominalize(clause.subject),
            )
            sentence = self._assertion(message, subject, grammatical_number)
        else:
            raise ValueError(f"unsupported communicative act: {act}")

        discourse.observe(clause)
        return sentence

    def _assertion(
        self, message: Message, subject: str, grammatical_number: str
    ) -> str:
        clause = message.clause
        if message.modality:
            predicate = self._predicate(clause, "base", include_negation=clause.negative)
            body = f"{subject} {message.modality} {predicate}"
        elif clause.negative:
            auxiliary = self._do_auxiliary(clause)
            predicate = self._predicate(clause, "base", include_negation=False)
            body = f"{subject} {auxiliary} not {predicate}"
        else:
            form = "past" if clause.tense == "past" else (
                "third" if grammatical_number == "singular"
                else "base"
            )
            body = f"{subject} {self._predicate(clause, form, include_negation=False)}"

        if message.cause:
            body += f" because {self._clause_body(message.cause)}"
        return body[0].upper() + body[1:] + "."

    def _question(self, message: Message) -> str:
        clause = message.clause
        subject = self._noun_phrase(clause.subject)
        if message.modality:
            predicate = self._predicate(clause, "base", include_negation=clause.negative)
            if message.question_word:
                return (
                    f"{message.question_word.capitalize()} {message.modality} "
                    f"{subject} {predicate}?"
                )
            return f"{message.modality.capitalize()} {subject} {predicate}?"
        auxiliary = self._do_auxiliary(clause)
        predicate = self._predicate(clause, "base", include_negation=clause.negative)
        if message.question_word:
            return (
                f"{message.question_word.capitalize()} {auxiliary} "
                f"{subject} {predicate}?"
            )
        return f"{auxiliary.capitalize()} {subject} {predicate}?"

    def _clause_body(self, clause: Clause) -> str:
        subject = self._noun_phrase(clause.subject)
        if clause.negative:
            predicate = self._predicate(clause, "base", include_negation=False)
            return f"{subject} {self._do_auxiliary(clause)} not {predicate}"
        form = "past" if clause.tense == "past" else (
            "third" if clause.subject.number == "singular" else "base"
        )
        return f"{subject} {self._predicate(clause, form, include_negation=False)}"

    def _predicate(self, clause: Clause, form: str, *, include_negation: bool) -> str:
        verb = self._verb(clause.verb, form)
        if clause.object is not None:
            verb += f" {self._noun_phrase(clause.object)}"
        if clause.adverb:
            verb += f" {self._word('adverbs', clause.adverb)}"
        if include_negation:
            return f"not {verb}"
        return verb

    def _do_auxiliary(self, clause: Clause) -> str:
        if clause.tense == "past":
            return "did"
        return "does" if clause.subject.number == "singular" else "do"

    def _noun_phrase(self, entity: Entity, *, pronominalize: bool = False) -> str:
        if entity.lemma not in self.lexicon["nouns"]:
            raise ValueError(f"unknown noun concept: {entity.lemma}")
        noun = self.lexicon["nouns"][entity.lemma]
        if entity.number not in {"singular", "plural"}:
            raise ValueError(f"unsupported noun number: {entity.number}")
        if entity.determiner not in {"", "a", "an", "the", "this", "that", "some"}:
            raise ValueError(f"unsupported determiner: {entity.determiner}")
        if entity.number == "plural" and entity.determiner in {"a", "an"}:
            raise ValueError("plural noun phrases cannot use a or an")
        if pronominalize:
            return self._pronoun(entity)

        parts: list[str] = []
        if entity.determiner and not entity.proper:
            determiner = entity.determiner
            if determiner == "a" and noun["singular"][0].casefold() in "aeiou":
                determiner = "an"
            parts.append(determiner)
        parts.extend(self._word("adjectives", adjective) for adjective in entity.adjectives)
        parts.append(noun[entity.number])
        phrase = " ".join(parts)
        return phrase if not entity.proper else phrase[0].upper() + phrase[1:]

    def _pronoun(self, entity: Entity) -> str:
        noun = self.lexicon["nouns"][entity.lemma]
        return (
            entity.pronoun
            or noun.get("pronoun")
            or ("they" if entity.number == "plural" else "it")
        )

    def _number_in_context(self, entity: Entity, *, pronominalize: bool) -> str:
        if not pronominalize:
            return entity.number
        return "plural" if self._pronoun(entity) in {"they", "we"} else "singular"

    def _verb(self, lemma: str, form: str) -> str:
        if lemma not in self.lexicon["verbs"]:
            raise ValueError(f"unknown verb concept: {lemma}")
        return self.lexicon["verbs"][lemma][form]

    def _word(self, category: str, lemma: str) -> str:
        try:
            return self.lexicon[category][lemma]
        except KeyError as error:
            raise ValueError(f"unknown {category[:-1]} concept: {lemma}") from error

    def _validate(self, message: Message) -> None:
        if message.act not in {"assert", "question", "request"}:
            raise ValueError(f"unsupported communicative act: {message.act}")
        self._validate_clause(message.clause)
        if message.modality not in {None, "may", "might", "can", "could", "must", "should"}:
            raise ValueError(f"unsupported modality: {message.modality}")
        if message.question_word not in {None, "why", "how", "when", "where", "what"}:
            raise ValueError(f"unsupported question word: {message.question_word}")
        if message.question_word and message.act != "question":
            raise ValueError("question words require a question act")
        if message.cause:
            self._validate_clause(message.cause)
            if message.act != "assert":
                raise ValueError("causal clauses are currently supported for assertions only")
        if message.act == "request" and message.cause:
            raise ValueError("requests with causal clauses are not supported")

    def _validate_clause(self, clause: Clause) -> None:
        if clause.tense not in {"present", "past"}:
            raise ValueError(f"unsupported tense: {clause.tense}")
        if clause.subject.number not in {"singular", "plural"}:
            raise ValueError(f"unsupported subject number: {clause.subject.number}")
        self._noun_phrase(clause.subject)
        self._verb(clause.verb, "base")
        if clause.object:
            self._noun_phrase(clause.object)
        if clause.adverb:
            self._word("adverbs", clause.adverb)


def _entity(data: dict[str, Any] | None) -> Entity | None:
    if data is None:
        return None
    return Entity(
        lemma=data["lemma"],
        number=data.get("number", "singular"),
        determiner=data.get("determiner", "the"),
        adjectives=tuple(data.get("adjectives", [])),
        proper=data.get("proper", False),
        pronoun=data.get("pronoun"),
    )


def _clause(data: dict[str, Any]) -> Clause:
    subject = _entity(data["subject"])
    assert subject is not None
    return Clause(
        subject=subject,
        verb=data["verb"],
        object=_entity(data.get("object")),
        tense=data.get("tense", "present"),
        negative=data.get("negative", False),
        adverb=data.get("adverb"),
    )


def message_from_dict(data: dict[str, Any]) -> Message:
    return Message(
        act=data["act"],
        clause=_clause(data["clause"]),
        modality=data.get("modality"),
        cause=_clause(data["cause"]) if data.get("cause") else None,
        question_word=data.get("question_word"),
    )


def surface_constraints(
    message: Message, utterance: str, speaker: AioLanguage | None = None
) -> dict[str, bool]:
    """Check observable realization of the frame's required semantic operators."""
    language = speaker if speaker is not None else AioLanguage()
    words = TOKEN_PATTERN.findall(utterance.casefold())
    word_set = set(words)
    clause = message.clause
    role_order = True
    subject = clause.subject
    obj = clause.object
    expected_verb_form = "base"
    if (
        message.act == "assert"
        and not clause.negative
        and not message.modality
        and clause.tense == "past"
    ):
        expected_verb_form = "past"
    elif (
        message.act == "assert"
        and not clause.negative
        and not message.modality
        and clause.tense == "present"
        and clause.subject.number == "singular"
    ):
        expected_verb_form = "third"
    verb_form = language.lexicon["verbs"][clause.verb][expected_verb_form]
    verb_present = verb_form.casefold() in word_set
    if message.act == "request" and obj is not None:
        verb_positions = [i for i, word in enumerate(words) if word == verb_form]
        object_positions = [
            i
            for i, word in enumerate(words)
            if word == language.lexicon["nouns"][obj.lemma][obj.number].casefold()
        ]
        role_order = bool(verb_positions and object_positions) and (
            verb_positions[0] < object_positions[0]
        )
    elif obj is not None:
        subject_word = language.lexicon["nouns"][subject.lemma][subject.number].casefold()
        object_word = language.lexicon["nouns"][obj.lemma][obj.number].casefold()
        subject_positions = [i for i, word in enumerate(words) if word == subject_word]
        object_positions = [i for i, word in enumerate(words) if word == object_word]
        verb_positions = [i for i, word in enumerate(words) if word == verb_form]
        role_order = bool(subject_positions and object_positions and verb_positions) and (
            subject_positions[0] < verb_positions[0] < object_positions[0]
        )

    if clause.negative:
        polarity = "not" in word_set
    else:
        polarity = True
    if message.modality:
        modality = message.modality in word_set
    else:
        modality = True
    if message.act == "question":
        act = utterance.rstrip().endswith("?")
        if message.question_word:
            act = act and words[:1] == [message.question_word]
    elif message.act == "request":
        act = bool(words and words[0] == "please")
    else:
        act = utterance.rstrip().endswith(".")
    if message.cause:
        relation = "because" in word_set
    else:
        relation = True

    expected_subject = language.lexicon["nouns"][subject.lemma][subject.number]
    adjectives_present = all(
        adjective.casefold() in word_set for adjective in subject.adjectives
    )
    if obj:
        adjectives_present = adjectives_present and all(
            adjective.casefold() in word_set for adjective in obj.adjectives
        )
    adverb_present = clause.adverb is None or (
        language.lexicon["adverbs"][clause.adverb].casefold() in word_set
    )
    past = True
    if clause.tense == "past" and not message.modality:
        if message.act == "question" or clause.negative:
            past = "did" in word_set
        else:
            past = language.lexicon["verbs"][clause.verb]["past"].casefold() in word_set
    plural_agreement = True
    if (
        clause.subject.number == "plural"
        and clause.tense == "present"
        and not clause.negative
        and not message.modality
        and message.act == "assert"
    ):
        plural_agreement = verb_form == language.lexicon["verbs"][clause.verb]["base"]

    return {
        "subject_present": message.act == "request"
        or expected_subject.casefold() in word_set,
        "object_present": obj is None
        or language.lexicon["nouns"][obj.lemma][obj.number].casefold() in word_set,
        "adjectives_present": adjectives_present,
        "adverb_present": adverb_present,
        "role_order": role_order,
        "verb_form": verb_present,
        "polarity": polarity,
        "modality": modality,
        "communicative_act": act,
        "causal_relation": relation,
        "past_tense": past,
        "plural_agreement": plural_agreement,
    }


def main() -> None:
    import argparse

    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("frame", type=Path, help="JSON file containing one message frame")
    args = parser.parse_args()
    frame = json.loads(args.frame.read_text(encoding="utf-8"))
    print(AioLanguage().speak(message_from_dict(frame)))


if __name__ == "__main__":
    main()
