# Aio language foundation: a proposal, not a result

## Why begin here

Aio should not confuse three different abilities:

- **Knowledge:** what propositions or experiences it can retrieve.
- **Language:** how it understands and produces communicative signals.
- **Reasoning:** how it changes or evaluates beliefs using evidence and rules.

A system can know a fact and express it badly; speak smoothly while making
things up; or reason correctly in a small symbolic world without knowing much
about the world outside it. We should measure these abilities separately
before claiming that one has improved.

The current Aio-0 is an evidence-retrieval prototype with hand-written answer
rules. It does not yet learn a grammar, understand open-ended language, or
produce general fluent conversation. This document proposes what to build and
how to tell whether it works.

## Aio's working definition of language

> **Language is a learned, shared system of signals and conventions through
> which agents coordinate attention, communicate intentions and models of a
> situation, and revise their shared understanding across contexts.**

A message is not just a sentence-shaped string. It is a communicative act
whose interpretation depends on at least:

1. **Signal:** the spoken, written, signed, or otherwise perceived form.
2. **Convention:** learned associations between forms, constructions, and
   possible interpretations.
3. **Composition:** how parts combine into participants, events, properties,
   relations, and scope.
4. **Context:** what the participants are attending to, what has already been
   said, and what they can perceive or remember.
5. **Intent and effect:** whether the speaker is asserting, asking, requesting,
   imagining, correcting, joking, or doing something else—and how the listener
   updates its understanding.
6. **Feedback:** confirmation, confusion, correction, and repair that can
   change the interpretation or the learned conventions.

Under this definition, meaning is not merely a word's dictionary entry. It is
the structured interpretation a listener can use in context, including what is
known, what is being proposed, who said it, and how certain it is. One signal
can have several interpretations; ambiguity should be represented rather than
silently guessed away.

Language includes more than factual reports. Questions, instructions, stories,
hypotheticals, jokes, emotional signals, and acts of politeness have meaning
even when they do not assert a fact. Aio must eventually model those acts, not
reduce all conversation to retrieving a true sentence from a book.

## Fluency is an observable behavior

For Aio, **fluency** means reliably producing and understanding messages that
are:

- structurally well-formed enough to understand;
- coherent with the current conversation;
- appropriate to the speaker's communicative goal and the listener;
- easy to follow without repeated clarification; and
- faithful to the meaning and uncertainty the system intended to express.

Fluency is not factual accuracy, eloquence, verbosity, or confidence. A short
plain answer can be fluent. A polished answer that invents evidence is not a
successful Aio answer.

Fluency requires linguistic experience: a system cannot learn the conventions
of English from no English exposure. The research question is whether
compositional representations, interaction, grounding, and feedback can make
that learning more data-efficient and generalize better than memorizing many
surface continuations. The claim is **not** that language data is unnecessary.

## What this definition commits us to build

The proposed unit passed between Aio's reader, reasoner, and speaker is an
explicit **message frame**:

```text
communicative_act: assert | ask | request | imagine | correct | ...
content: structured entities, events, relations, and operators
context: active participants, referents, and discourse focus
stance: certainty, possibility, negation, source, and speaker commitment
```

For example, “The west tray may have wilted because its soil dried out” is not
one undifferentiated string. It expresses an event and a candidate cause, with
uncertainty and a speaker commitment weaker than certainty. The book's
observation is a different object from Aio's inference about that observation.
Keeping those apart lets the speaker say “may have” rather than accidentally
turning a hypothesis into a fact.

The first implementation should be deliberately small and inspectable:

### 1. A discourse state

Track who is speaking, what entities are currently in focus, what the question
asks for, and which claims are shared or disputed. Update this state after
every message. Do not make a one-turn answerer pretend every utterance is
independent.

### 2. A compositional meaning representation

Represent propositions and speech acts with typed records or a graph. Support
participants and roles, properties, event time, negation, questions, modality,
source, and confidence. Preserve links to the passage or interaction that
supports a claim. This is a working representation, not a claim that thought
is literally a graph.

### 3. A reader that returns alternatives

Map an utterance into one or more candidate message frames, using the
conversation and the knowledge book to resolve references. Keep competing
interpretations when evidence is insufficient. Ask a clarification question
when choosing the wrong interpretation would matter.

### 4. A learned construction inventory

Learn reusable form–meaning patterns from examples: for instance, how English
questions differ from assertions, how a causal explanation is phrased, or how
“might” changes commitment. A construction must combine with other
constructions; a library of whole-sentence templates is not compositional
understanding.

Start with a transparent grammar and a modest set of constructions. Learn
lexical choices, ordering, agreement, and context-sensitive alternatives from
correction and contrastive examples. Every rule or learned weight must be
inspectable enough to diagnose a bad answer.

### 5. A speaker that plans before wording

Start with the intended message frame, decide what the listener needs and what
is already shared, then choose a construction and words. Generate several
candidate wordings and rank them for meaning preservation, grammaticality,
coherence, audience fit, and brevity. A fluency reward must never override a
hard check that the wording preserves the intended certainty, negation, and
source.

### 6. A listener check and repair loop

Estimate what a listener would understand from a candidate wording. If the
likely interpretation loses a crucial distinction, choose another wording.
When the listener signals confusion, update the discourse state and repair the
message; do not simply repeat it more confidently.

These are hypotheses about useful engineering boundaries. They do not prove
that a human mind has these components or that a symbolic representation is
the unique correct one. They do create interfaces we can inspect and compare.

## How Aio could learn without relying on massive text scale

Aio should learn language through a mixture of:

- **Contrast:** examples that differ in one meaningful way, such as “did” vs.
  “might,” so the distinction has a learnable consequence.
- **Grounding:** messages paired with observable situations, actions,
  diagrams, or a small simulated world. Aio should learn what words refer to,
  not only which words co-occur.
- **Composition:** training on combinations withheld during learning. If Aio
  learns “the red block moves” and “the blue circle spins,” it should attempt
  “the red circle spins,” rather than needing that exact sentence memorized.
- **Dialogue:** questions, acknowledgements, interruptions, corrections, and
  requests for clarification. A speaker learns what works by observing a
  listener's response.
- **Feedback:** a tutor labels the misunderstanding or repairs the intended
  meaning. Prefer a correction that teaches a reusable distinction over
  another pile of unannotated prose.
- **Self-checks:** compare the generated sentence's parsed meaning to the
  intended frame; flag missing roles, changed polarity, unsupported certainty,
  or a lost source.
- **Exploration:** ask for examples that discriminate between the system's
  competing interpretations. Do not ask for a fact merely to appear curious.

This may reduce the number of examples needed for a narrow task; it is not
evidence that a small system can reach frontier-level language quality. A
child's language learning also includes years of rich, multimodal, social
experience. “Less text” is not “less experience.”

The project is also not starting from zero as a scientific field. Explicit
meaning representations, grammar induction, construction-based descriptions,
grounded communication, and dialogue repair all have prior research
traditions. Aio's contribution, if any, must be a demonstrated combination,
learning method, or result—not the fact that its components have a new name.

## The conclusion: what is possible, and what is not established

It is technically possible to build a language system whose core operation is
**constructing and communicating meaning**, rather than directly selecting
the next token from a huge pretrained text model. The first useful version can
combine a learned grammar, structured message frames, a discourse state, and a
speaker/listener loop. It can plausibly be more sample-efficient and easier to
audit in a bounded world.

It is **not** justified to conclude that this design will be more fluent than
a large language model, that it needs little total experience, that structured
meaning alone solves ambiguity, or that it will compete with a frontier model
in open-domain conversation. Fluent language is not a substitute for broad
linguistic exposure, and explicit rules introduce their own brittleness.

The sensible target is therefore a testable one: **make Aio a competent,
coherent speaker in a growing set of held-out situations, while tracking how
many examples it needed and whether it preserves meaning.** If the approach
cannot outperform a simple template/grammar baseline on compositional
generalization, repair, and sample efficiency, revise it. Do not describe a
smoke-test score as general intelligence or a win over GPT-6.

## The first experiment

Build a small, controlled communication world with:

- a few named objects, attributes, actions, and relations;
- a limited English construction set for descriptions, questions, negation,
  requests, uncertainty, and causal explanations;
- paired scene/message examples and multi-turn corrections;
- a training split that withholds particular combinations, not just
  particular sentences; and
- a fixed evaluation split that every candidate system sees only at test time.

Compare Aio to (1) a hand-written template/grammar baseline and (2) a small
pretrained reference model given the same task information. Measure, separately:

1. **Meaning preservation:** did the listener recover the intended roles,
   polarity, modality, and source?
2. **Compositional generalization:** can Aio express and understand new
   combinations of familiar parts?
3. **Conversational success:** can it answer, clarify, and repair over several
   turns?
4. **Fluency:** blinded human ratings of naturalness, coherence, and ease of
   understanding—not model confidence or BLEU alone.
5. **Learning efficiency:** how quickly do those scores improve with the same
   number of demonstrations and correction opportunities?
6. **Calibration and failure:** does it ask or abstain when the interpretation
   or knowledge is insufficient, and can we locate why it failed?

Report the number and type of examples, exact test questions, baselines, and
all failures. Keep wording quality separate from knowledge questions by
testing the same meaning frames with unfamiliar entity names and randomized
attributes. This checks whether the language system learned usable
constructions rather than memorized the small world's facts.

## Next conceptual step

Once this language interface is concrete, define the next terms independently
and operationally:

- **Understanding:** recovering an intended message frame with calibrated
  uncertainty and context-sensitive references.
- **Thought:** maintaining and transforming candidate internal models before
  communicating them; not necessarily a private natural-language monologue.
- **Reasoning:** applying explicit or learned transformations to beliefs,
  assumptions, and evidence, while tracking provenance and uncertainty.
- **Intelligence:** achieving goals in unfamiliar situations by learning,
  generalizing, planning, and correcting errors under stated constraints.

These are proposed engineering definitions, not settled definitions of human
cognition. Each needs its own failure tests before Aio should claim to possess
it.
