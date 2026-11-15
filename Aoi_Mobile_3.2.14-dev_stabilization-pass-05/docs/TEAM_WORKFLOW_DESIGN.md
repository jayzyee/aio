# Aoi team workflow and knowledge design

## Research interpretation

The user's phrase “Teamly AI” was interpreted as a reference to **Teamily AI** (`https://teamily.ai/`) and the separate **Teamly** knowledge/workflow product (`https://www.teamly.com/`). They solve overlapping but different problems:

- Teamily AI presents agent teams inside conversations, collaborative workspaces/studios, shared context and memory, model routing, reusable connectors/skills, and the ability to delegate multi-step work.
- Teamly's knowledge-management product focuses on centralised team knowledge, searchable AI answers, structured articles/spaces, SOPs and learning/onboarding material.

Aoi combines the useful patterns while keeping its own architecture and interface. This is not a rebrand, an official integration, or a claim of feature parity with either product.

## Current Aoi workflow

### 1. Project context

A project has a title, goal, conventional notes and project-specific workflow data. The workflow record persists independently from individual conversations and stores:

- dependency-aware tasks, owner role, priority, acceptance criteria, attempts and reviewer feedback;
- recorded decisions, treated as project constraints in later project chats;
- knowledge notes and tagged searchable content;
- reusable playbooks/SOPs with a trigger and ordered steps;
- specialist role status, activity, tool results, approval and denial events.

### 2. Specialist flow

`Planner → Researcher → Engineer → Reviewer → Human approval`

- **Planner** creates a structured plan with dependencies and acceptance criteria.
- **Researcher** gathers background, inspects public repositories and retrieves project memory. It is read-only.
- **Engineer** works on one assigned task and can request commands or repository changes through approval cards.
- **Reviewer** inspects evidence, checks acceptance and can request revisions. It cannot request implementation file writes or repository changes.
- **Human approval** is the only route from `Review` to `Done`. A revision request returns the task to `To do` with the user's feedback.

A downstream task cannot start until all referenced dependency tasks are marked `Done` by the user. The UI shows each stage, agent role, task state, review state and activity history.

### 3. Tool execution

The model does not execute tools itself. It can request one structured Aoi tool call at a time. Aoi validates the action, presents approval for commands/writes/external changes, runs the action through `ToolRunner`, appends the actual result to the originating conversation and records the result in the project activity history. The assistant is then asked to continue using that returned result.

Consequential actions requiring an approval card include Linux shell commands and writes, Piston code execution, GitHub branch/file/issue/PR mutations, project knowledge writes, decision capture and playbook writes. Read-only repository and workspace operations do not require a mutation approval.

### 4. Knowledge and SOPs

Project knowledge is intentionally scoped by project rather than mixed into casual conversations. It includes:

- **Notes:** research, architecture, constraints, findings and reference material.
- **Decisions:** choices and trade-offs that later agents should respect.
- **Playbooks:** repeatable procedures with a “Use when…” trigger and ordered steps.

The current search is bounded lexical matching over project goal, notes, decisions, saved knowledge, playbooks and task records. The current model receives a selected set of recent notes and playbooks in project context, and can request additional project knowledge search. This is not yet vector/semantic retrieval, a multi-user wiki, a permissioned organisation knowledge base, or a document ingestion pipeline.

## Important architecture limits

- Planner, Researcher, Engineer and Reviewer are specialist prompt roles routed through the user's currently selected model/provider. They are not four independent hosted model instances and do not run concurrently in this build.
- The workflow is resumable and approval-gated, but unattended autonomous agents and scheduled work have not been implemented.
- Browser service cards are launch destinations, not API integrations. Only cards explicitly described as native AI-callable tools can be invoked from an Aoi conversation.
- The earlier local Linux bridge was a convenience for a trusted single-user Termux/desktop workspace, not a hardened command sandbox. The current 3.2.14 recommendation is a remote Codespaces workspace; its shell still inherits the remote workspace user's permissions.

## Next architecture milestones

1. Add vector/hybrid retrieval with source attribution, relevance filters and user-visible citations for project files.
2. Add project document ingestion, article versioning, comments and cross-project knowledge linking.
3. Add a more strongly isolated execution backend with explicit filesystem, network, CPU, memory and timeout controls; do not describe the Codespaces shell as sandboxed.
4. Add pluggable specialist model routing, bounded parallel subtasks, cancellation propagation and per-agent cost/time reporting.
5. Add reusable, versioned skills with schemas, permission classes, test fixtures, audit logs and one-click enable/disable.
6. Add robust Git local workspace operations (status/diff/commit) behind the Linux bridge or a dedicated companion API, in addition to the current GitHub REST actions.
7. Add integration contract tests against isolated GitHub fixtures and a real Codespaces cloud-workspace acceptance test.
