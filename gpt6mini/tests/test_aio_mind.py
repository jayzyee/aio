import unittest

from gpt6mini.aio_mind import AioMind


class AioMindTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.mind = AioMind()

    def test_infers_a_plausible_reason_and_keeps_caveat(self) -> None:
        result = self.mind.answer("Why did the west tray wilt?")

        self.assertFalse(result["abstained"])
        self.assertIn("Dry soil may have contributed", result["answer"])
        self.assertIn("controlled experiment", result["answer"])
        self.assertIn("The West and East Trays", result["answer"])

    def test_abstains_when_the_book_has_no_evidence(self) -> None:
        result = self.mind.answer("What is the capital city of France?")

        self.assertTrue(result["abstained"])
        self.assertEqual(result["evidence"], [])

    def test_reader_question_uses_its_relevant_section(self) -> None:
        result = self.mind.answer("What should a careful reader separate?")

        self.assertIn("Reading an Observation", result["answer"])
        self.assertIn("inference", result["answer"])
        self.assertIn("concludes", result["answer"])

    def test_interprets_a_contrast_without_claiming_proof(self) -> None:
        result = self.mind.answer(
            "What does the east tray's condition tell us about the role of moisture?"
        )

        self.assertIn("consistent with soil moisture", result["answer"])
        self.assertIn("controlled experiment", result["answer"])

    def test_proof_question_is_not_mistaken_for_a_why_question(self) -> None:
        result = self.mind.answer(
            "Why is a pattern not always proof of its explanation?"
        )

        self.assertFalse(result["answer"].startswith("No."))
        self.assertIn("plausible", result["answer"])
        self.assertIn("proving", result["answer"])
        self.assertNotIn("The West and East Trays", result["answer"])

    def test_retrieval_limit_must_be_positive(self) -> None:
        with self.assertRaises(ValueError):
            self.mind.retrieve("west tray", limit=0)


if __name__ == "__main__":
    unittest.main()
