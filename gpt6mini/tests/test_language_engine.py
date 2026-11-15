import json
import unittest
from pathlib import Path

from gpt6mini.language_engine import (
    AioLanguage,
    DiscourseState,
    Entity,
    Message,
    Clause,
    message_from_dict,
    surface_constraints,
)


ROOT = Path(__file__).parents[1]


class AioLanguageTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.language = AioLanguage()
        path = ROOT / "benchmarks" / "language_cases.jsonl"
        cls.cases = [
            json.loads(line) for line in path.read_text(encoding="utf-8").splitlines()
        ]

    def test_composes_every_held_out_message_frame(self) -> None:
        for case in self.cases:
            with self.subTest(case=case["id"]):
                message = message_from_dict(case["frame"])
                utterance = self.language.speak(message)
                self.assertTrue(
                    all(surface_constraints(message, utterance, self.language).values()),
                    utterance,
                )
                tokens = utterance.casefold().replace("?", "").replace(".", "").split()
                self.assertTrue(
                    all(anchor.casefold() in tokens for anchor in case["expected_anchors"]),
                    utterance,
                )

    def test_discourse_state_allows_a_contextual_pronoun(self) -> None:
        subject = Entity("robot")
        state = DiscourseState(last_subject=subject, turn_count=1)
        message = Message(
            act="assert",
            clause=Clause(subject=subject, verb="wait"),
        )

        self.assertEqual(self.language.speak(message, state, use_pronoun=True), "It waits.")

    def test_human_pronoun_uses_plural_agreement(self) -> None:
        subject = Entity("courier")
        state = DiscourseState(last_subject=subject, turn_count=1)
        message = Message(
            act="assert",
            clause=Clause(subject=subject, verb="carry", object=Entity("map")),
        )

        self.assertEqual(
            self.language.speak(message, state, use_pronoun=True),
            "They carry the map.",
        )

    def test_question_operator_is_not_lost(self) -> None:
        case = next(case for case in self.cases if case["id"] == "why_question")
        message = message_from_dict(case["frame"])

        self.assertEqual(self.language.speak(message), "Why does the owl watch the garden?")

    def test_modal_assertion_keeps_subject_before_modal(self) -> None:
        case = next(case for case in self.cases if case["id"] == "possibility")
        message = message_from_dict(case["frame"])

        self.assertEqual(
            self.language.speak(message),
            "The small robot might inspect the crystal.",
        )

    def test_unknown_lexical_concept_fails_explicitly(self) -> None:
        message = Message(
            act="assert",
            clause=Clause(subject=Entity("unlisted_species"), verb="wait"),
        )

        with self.assertRaisesRegex(ValueError, "unknown noun"):
            self.language.speak(message)


if __name__ == "__main__":
    unittest.main()
