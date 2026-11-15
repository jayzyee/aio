# Aoi Mobile 3.2.9-dev — Engineering and visual review

**Base:** recovered 3.2.7 source + 3.2.8 approval/roadmap work  
**Engine:** Godot 4.8 beta1  
**Capture sizes:** 720 × 1520 and 720 × 1600 logical pixels  
**Scope:** safe composer behavior when a project tool belongs to a different conversation; approval and queue continuity retained.

## User-visible change

The composer no longer treats the shared ToolRunner as if it always belongs to the open conversation. Its Send/Stop affordance is now derived from the active chat's ownership context.

- In the chat that owns a running project tool, an empty composer can stop that work. A typed follow-up is queued against the same project/chat and waits for the existing tool/approval decision.
- In a different chat, the composer stays a normal Send action. Sending there does not cancel the background project tool or transfer its result into the unrelated conversation.
- The icon is refreshed after typing, chat switching, starting a new conversation and tool-state changes.
- Background tool state is not presented as activity in an unrelated conversation.
- When the tool returns, its result and queued follow-up are stored against the originating conversation.

## Carried-forward behavior

3.2.8 approval persistence and the detailed project plan contract remain in the source. The planner contract continues to require 5–14 meaningful tasks, project/file scope, descriptions, deliverables, observable acceptance and verification criteria, roles, priority, and valid dependency references. The 3.2.7 abstract Aoi identity, Signal Field/Spatial Prism, typography and reduced-motion foundations have not been discarded.

## Review captures

### Approval and queued follow-up

`approval_queue_720x1520.png` shows a project request, a waiting permission decision, and a later user message marked queued. The approval surface says that other work is preserved. The screenshot is a controlled presentation fixture; it demonstrates the composition and state hierarchy, not a live tool side effect.

### Independent chat during background work

`independent_chat_while_building_720x1520.png` shows a normal conversation with a regular Send affordance and no unrelated activity panel. This is also a controlled presentation fixture. The UI regression scenario separately constructs an originating tool session, switches to a different chat, sends a real mock-provider reply, and verifies that ToolRunner ownership remains with the original chat.

### Existing shell and creation references

`chat_empty_720x1600.png` and `creation_card_720x1600.png` remain included from the previous reviewed baseline. They were not redesigned in this milestone.

## Runtime verification supporting this milestone

- Godot 4.8 beta1 editor/import pass completed on the current source.
- Phone UI E2E ran against the local mock provider and reported `UI_SUMMARY 106/106 passed`, including the new composer ownership and independent-chat regression paths.
- Core logic probe reported `UNIT_SUMMARY 82/82 passed`.
- Project jobs reported `PROJECT_JOB_SUMMARY 21/21 passed`.
- Persistence recovery scenarios completed with `failures=0`. Error messages in that probe are deliberate corruption injections to prove last-known-good recovery, not an unhandled app crash.
- Touch-scroll flow was run in an Xvfb GUI window and reported `SCROLL_SUMMARY 8/8 passed` for drags beginning on reply text, user bubbles, setup cards, buttons and project text. A headless-only touch simulation had produced misleading failures because there was no GUI window; use the Xvfb result for this test.
- Chat shell behavior probe completed with `failures=0`.

These are internal verification signals, not product progress claims. A green test run does not establish physical-device reliability.

## Known limitations

- No physical Android device was attached. Keyboard/IME resizing, status-bar/cutout geometry, gesture navigation, process suspension/restart and rotation are not physically verified.
- The independent-chat screenshot is a presentation fixture; use the E2E regression and code path as behavior evidence.
- Long-running work across forced Android process death still requires a dedicated device lifecycle pass. Existing task/project persistence does not by itself prove full provider stream restoration after process termination.
- The final playable game-generation and landscape immersive hand-off remain unfinished product acceptance items.
- Godot 4.8 beta1 is the available engine from the user's Library; this is not stable Godot release certification.
- The aggregate all-suites runner is not being represented as a certified release gate in this checkpoint.

## Review decision

This milestone fixes a concrete interruption to conversation use: a running build in one chat no longer steals the composer in another chat or gets cancelled by an unrelated send. The current scroll implementation passed the GUI-backed swipe scenario, so no unnecessary scroll rewrite was made. The next product direction should address the larger remaining mismatch found in the 3.2.7 audit: **Project Home and Results** should focus on the user's goal, genuine progress and real artifacts, with GitHub/Linux/technical task machinery moved behind secondary details. Do not start that redesign by changing the visual language again; keep the existing chat shell, Signal Field, Inter and orbital icon foundations.
