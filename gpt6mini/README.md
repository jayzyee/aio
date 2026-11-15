# Aio GPT6 Mini

Aio-0 is an experimental, book-reading reasoning model: it learns a small
associative memory from source passages, activates related evidence for a
question, checks whether the evidence is strong enough to answer, then writes
a short source-grounded response.

It is a new, inspectable experiment—not GPT-6, a trained language model, or a
claim of general intelligence. It uses no neural-network weights or external
Python packages. Its scope is deliberately narrow: answer from the supplied
book, explain a simple evidence-based inference, and abstain when the book
cannot support an answer.

## What is different about Aio-0

The model has five explicit stages:

1. **Book encoding:** each book is split into source-labelled sentence traces.
   Inverse document frequency gives distinctive terms more weight.
2. **Associative learning:** a sparse Hebbian graph links traces that share
   concepts, plus neighboring traces in the same section.
3. **Resonance:** question activation spreads through that graph for two rounds
   while keeping the original question signal:
   `h_next = 0.78 * question_signal + 0.22 * graph_context`.
4. **Evidence gate:** a minimum direct-match threshold blocks answers when the
   book has no meaningful match. Retrieved uncertainty notes travel with the
   evidence they qualify.
5. **Reader/writer:** a small, explicit inference layer distinguishes a
   plausible explanation from a proven cause. The writer uses source text,
   cites its section, and abstains rather than inventing missing facts.

The association graph is learned from the book when `AioMind` is initialized.
The answer templates and causal rules are hand-authored and inspectable; this
is not fine-tuning, and fluent wording remains limited. The goal is to
experiment with a different reasoning structure, not to imply it is stronger
than large language models.

The proposed next research direction—language as communicative intent,
composition, discourse, and feedback—is defined in
[language_foundation.md](language_foundation.md). That proposal is not yet
implemented in Aio-0.

## Run Aio-0

From the repository root:

```sh
python3 gpt6mini/aio_mind.py "Why did the west tray wilt?"
python3 gpt6mini/aio_mind.py "What is the capital city of France?"
```

The first answer cites the book and labels the causal explanation as plausible;
the second abstains because the sample book does not contain that fact. Add
source-labelled passages to `knowledge/books.json` to give the reader more to
learn from.

## Generate a comparison report

The six-case smoke test compares Aio-0 with the original lexical-search
baseline. It reports answerability, answer-anchor coverage, evidence
coverage, and a small grounded-task proxy, and prints every answer for
inspection:

```sh
python3 gpt6mini/benchmark.py
```

To compare the same questions with a small pretrained model running locally,
install the optional CPU dependencies and request Qwen:

```sh
python3 -m venv gpt6mini/.venv
gpt6mini/.venv/bin/pip install -r gpt6mini/requirements-reference.txt
gpt6mini/.venv/bin/python gpt6mini/benchmark.py --qwen
```

This downloads `Qwen/Qwen2.5-0.5B-Instruct` from Hugging Face and runs it on
CPU. The Qwen model is a reference baseline, not part of Aio-0. The comparison
gives both systems the same source book. A six-question smoke test is not a
scientific fluency evaluation; fluency is shown in the answer samples for
human comparison, while measured scores cover only the listed task checks.

Run the focused tests with:

```sh
python3 -m unittest gpt6mini.tests.test_aio_mind -v
```

## Files

- `aio_mind.py` — Aio-0's learned evidence graph, resonance, answer gate, and
  constrained response generator.
- `knowledge/books.json` — the sample book.
- `benchmarks/cases.jsonl` — small, explicit evaluation set.
- `benchmark.py` — lexical and optional Qwen comparison runner.
- `training_examples.jsonl` — source-first examples for a future model adapter;
  these examples are not used to train an LLM.
- `student_system_prompt.md` — optional instructions for an external model host.
- `tools/search_knowledge.py` — standalone JSON search tool.
