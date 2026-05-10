# Symphony-informed Linear orchestration

This note captures the research pass for the Linear project
[Configure Linear](https://linear.app/rzp-labs/project/configure-linear-3d0261d38831), now under the
`rzpONE` Linear team (`ONE`). It is deliberately a design translation, not a proposal to blindly run
OpenAI's Symphony reference service as-is.

## Executive take

Symphony is useful here less as software and more as an operating model:

- Linear is the **control plane** for work selection, handoffs, approvals, and auditability.
- Repo-owned workflow policy is the **execution contract** for how agents act, validate, and hand off.
- Linear templates, statuses, labels, automations, project docs, and issue comments are the **operating
  system** that makes agent work repeatable.
- Agent execution still needs isolated workspaces and evidence, but that isolation does not require
  adopting Hermes Kanban.

The goal is **not** to recreate Symphony, and it is **not** to adopt Hermes Kanban. The goal is to
translate Symphony's lessons into a Linear-native system that gives us high quality, high velocity,
and high repeatability with much less upfront machinery.

## Sources reviewed

Primary sources:

- OpenAI project description in Linear for `Configure Linear`.
- OpenAI Symphony repository: <https://github.com/openai/symphony>
- Symphony language-agnostic spec: <https://github.com/openai/symphony/blob/main/SPEC.md>
  (reviewed from a local research clone at commit `58cf97da06d556c019ccea20c67f4f77da124bf3`).
- Symphony Elixir reference implementation README and `WORKFLOW.md`.
- Local Hermes/Linear operating constraints and the user's explicit decision not to use Hermes Kanban
  for this workflow.

Notes:

- OpenAI's marketing/article pages were bot-gated from this environment, but the Linear project
  description includes the critical links and the repository/spec contain the operational details
  that matter for configuration.

## What Symphony actually is

Symphony is a long-running orchestrator that:

1. polls Linear for candidate issues,
2. creates/reuses one workspace per issue,
3. launches Codex app-server in that workspace,
4. feeds Codex a rendered issue prompt from a repo-owned `WORKFLOW.md`,
5. observes progress, retries failures, and stops work when Linear state makes the run ineligible.

The important boundary: Symphony is primarily a **scheduler/runner and tracker reader**. It does not
try to encode all ticket mutation logic in the orchestrator. Ticket comments, state transitions, PR
links, and completion semantics live in the workflow prompt/tooling that the coding agent receives.

That maps cleanly to Linear if we keep the layers separate:

| Symphony concept | Linear-native equivalent |
|---|---|
| Tracker polling | Filtered Linear views: ready work, active work, review, blocked, approved |
| `WORKFLOW.md` repo contract | Repo-owned execution guide plus Linear project/issue templates |
| Orchestrator state | Linear issue state, assignee, labels, dependencies, comments, attachments |
| Per-issue workspace | Required issue field/comment: working directory, branch, PR, environment stamp |
| Agent runner | The human/agent session that claims the issue and follows the template/guide |
| Dashboard/logs | Linear views, project docs, issue comments, PR checks, linked evidence |
| Handoff state | `Review`, `Approved`, `Done`, plus explicit blocked/rework conventions |

## Current local facts

- rzpONE team states currently include:
  - `Triage`
  - `Backlog`
  - `Todo`
  - `Active`
  - `Review`
  - `Approved`
  - `Done`
  - `Canceled`
  - `Duplicate`

## Recommended Linear workflow mapping

Do not copy Symphony's sample statuses (`Human Review`, `Merging`, `Rework`) mechanically. The
current rzpONE states are already close. I would use them like this:

| rzpONE state | Linear-native orchestration meaning | Transition source / rules |
|---|---|---|
| `Triage` | Raw intake queue | Special Linear-agent review state: identify related issues, duplicates, labels, assignee recommendations, and relationships before human/agent scheduling |
| `Backlog` | Accepted but not scheduled | No active delivery work; may be refined or prioritized |
| `Todo` | Ready to start | Must have a complete issue template, acceptance criteria, and validation plan; moves automatically to `Active` when a commit is made on a branch matching the configured issue-branch regex |
| `Active` | Branch has real work underway | Entered by branch/commit automation; maintain progress/evidence in issue comments and commits |
| `Review` | PR is open | Entered automatically when a PR is opened for the linked branch/issue |
| `Approved` | PR has been approved | Entered automatically when the PR receives approval; only landing/release/closeout work remains |
| `Done` | Merged to main | Entered automatically after merge to `main`; completion evidence should already be linked by PR/checks/comments |
| `Canceled` / `Duplicate` | Terminal non-success | Reason must be explicit |

The core workflow is therefore mostly branch/PR-driven, not manually state-driven. The operating model
must make branch naming non-negotiable: if the branch does not match the expected regex, the automatic
state machine breaks.

Required branch format: **`username/identifier-title`**.

For Yui-owned work, branches must use:

```text
yui/ONE-{n}-{issue-title}
```

Example:

```text
yui/ONE-9-define-ai-orchestration-operating-model
```

Why this one:

- the namespace identifies the actor/tool context (`yui`, `codex`, etc.),
- the issue key remains immediately after the namespace, so Linear/GitHub integrations still see the
  routing token early,
- it avoids the misleading `feature/` prefix for docs, ops, research, config, and chore work,
- it keeps enough title context to be useful in GitHub/GitButler without opening Linear,
- it fits tools like Codex that naturally produce `codex/<branch-name>`.

Use bare `identifier` only for throwaway automation where a human-readable branch name is actively
harmful. Otherwise, `username/identifier-title` is the default branch contract. We do **not** need
separate `Rework`, `Merging`, or `Human Review` states unless the branch/PR automation proves
insufficient.

## Linear template taxonomy

The Configure Linear project should produce these templates before any large-scale issue migration:

### 1. Project template: AI-orchestrated software project

Required sections:

- Purpose / outcome.
- Repository or workspace roots.
- Workflow contract location (`AGENTS.md`, `.agents/skills/*`, optional `WORKFLOW.md`).
- Required branch naming pattern / Linear issue regex.
- Linear state mapping and the branch/PR automation that drives it.
- Eligible agents/profiles and their responsibilities.
- Quality gates.
- Required evidence for completion.
- Handoff states and who acts next.
- Retry/block policy.
- Observability links: Linear views, PRs, checks, logs, dashboards, issue comments.

### 2. Research/spike issue template

Required sections:

- Research question.
- Sources that must be read.
- Decision criteria.
- Output shape.
- Non-goals.
- Evidence required.

### 3. Implementation issue template

Required sections:

- Problem statement.
- Scope / non-scope.
- Acceptance criteria.
- Validation commands.
- Repo/workspace.
- Branch naming pattern and expected issue key/regex.
- Branch/PR expectations.
- Rollback boundary.
- Dependencies/blockers.

### 4. Review/approval issue template

Required sections:

- Artifact under review.
- Review checklist.
- Required checks/CI.
- Human approval criteria.
- How to request rework.
- What state to move to after approval.

### 5. Operations/automation issue template

Required sections:

- Runtime/service affected.
- Configuration files.
- Secrets/auth dependencies.
- Dry-run command.
- Activation/deploy command.
- Health checks.
- Rollback command.

## Repo-owned workflow contract

Symphony's best idea is `WORKFLOW.md`: policy versioned with the repo instead of living in one
person's head. For this repo, we should not introduce a new file casually because `AGENTS.md` and
`.agents/skills/*` already carry a lot of policy. A good local convention would be:

1. `AGENTS.md` remains the repo-wide ground truth.
2. `.agents/skills/<domain>/SKILL.md` holds reusable methodology.
3. `docs/guides/*` holds human-readable architecture/runbooks.
4. A future `WORKFLOW.md` is only added if automation needs a single machine-readable
   orchestration contract with front matter.

If we add `WORKFLOW.md`, it should be thin front matter + a prompt body that imports/points to the
real skills, not a giant duplicate of `AGENTS.md`.

## Linear-native operating model

The Symphony lesson is not "use a board daemon". It is "make the implicit execution loop explicit".
In Linear, that means we need artifacts that answer these questions for every project and every issue:

1. Is this work specified enough to start?
2. Who or what is allowed to claim it, and what branch name must they use?
3. What context must be loaded before work starts?
4. What evidence proves the work is complete?
5. What state should it move to after execution, and should that transition be automatic?
6. How does review, rework, approval, and closeout happen?
7. Where does an operator look when something is blocked, stale, or suspicious?

This should be implemented with Linear-native pieces first:

- team workflow state semantics,
- project templates,
- issue templates,
- project documents,
- labels/components,
- saved views,
- automation rules,
- issue relations/dependencies,
- PR/check/evidence links,
- persistent issue comments for workpads and handoffs.

## Artifact set to create

### Guides / docs

1. **AI delivery operating model**
   - Defines the lifecycle from idea to done.
   - Explains what each rzpONE state means.
   - Defines who/what can move an issue between states.

2. **Agent execution guide**
   - How an agent claims work.
   - Required first actions: read issue, read linked docs, inspect repo, create/update workpad.
   - Required last actions: validation evidence, handoff summary, state transition.

3. **Review and approval guide**
   - What reviewers check.
   - Difference between `Review`, `Approved`, and `Done`.
   - Rework path without losing context.

4. **Evidence standard**
   - Defines acceptable proof: command output, CI link, screenshots, logs, PR review, runtime health check.
   - Explicitly rejects "works, sort of" handoffs.

5. **Blocked/stale work guide**
   - When to mark blocked.
   - Required blocker format.
   - Stale `Active` issue policy.

### Linear views

Create saved views for:

- `Ready to claim`: `Todo`, unblocked, prioritized.
- `Active work`: `Active`, grouped by assignee.
- `Needs review`: `Review`.
- `Approved to land`: `Approved`.
- `Blocked`: blocked issues or blocker label.
- `Stale active`: `Active` with no recent update.
- `No validation`: active/review issues missing validation/evidence labels or checklist.
- `No owner`: ready/active issues without assignee.

### Labels / components

Recommended labels:

- `kind:research`, `kind:implementation`, `kind:review`, `kind:ops`, `kind:docs`
- `agent-ready`, `needs-spec`, `blocked`, `needs-human`, `risky-change`
- `evidence:ci`, `evidence:manual`, `evidence:runtime`, `evidence:review`
- `handoff:review`, `handoff:approved`, `handoff:blocked`

Keep labels boring and operational. Cute taxonomies rot fast.

### Automations

Candidate automations:

- New issue without required template fields -> keep/move to `Triage` or add `needs-spec`.
- Move to `Todo` requires acceptance criteria and validation section.
- Move to `Active` assigns owner if missing and prompts for a workpad comment.
- Move to `Review` requires evidence link/comment and PR link if code changed.
- Move to `Approved` requires reviewer/human approval signal.
- Move to `Done` requires final evidence and closeout summary.
- `Active` without update after threshold -> label `stale` or notify.
- Blocked issue requires blocker reason and dependency relation when applicable.

Some of these may need API/scripts rather than built-in Linear automations. That is fine; document the
rules first, automate only once the shape proves useful.

### Visuals

Create three visuals for operator clarity:

1. **State machine diagram**
   - `Triage -> Backlog -> Todo -> Active -> Review -> Approved -> Done`
   - rework path from `Review` back to `Active`
   - terminal paths to `Canceled` / `Duplicate`

2. **Issue anatomy diagram**
   - title, problem, scope, acceptance criteria, validation, evidence, links, workpad.

3. **Handoff ladder**
   - implementation handoff, review handoff, approval handoff, done closeout.

## Quality gates to encode in Linear

Every implementation issue should require:

- explicit acceptance criteria,
- concrete validation command(s),
- evidence pasted into the issue/workpad/comment,
- branch/PR link when code changes,
- rollback note for risky changes,
- human/reviewer handoff when the agent cannot verify externally.

Every research issue should require:

- sources read,
- assumptions,
- recommendation,
- alternatives rejected,
- confidence/risk notes,
- follow-up issues if the answer implies work.

## Observability baseline

Linear should expose enough runtime truth that an operator can answer "what is happening?" without
reading a whole chat transcript:

- one persistent workpad/progress comment per active issue,
- state changes are primarily automated by branch commits, PR opens, PR approvals, and merges,
- PR/check/runtime evidence linked from the issue,
- saved views for ready/active/review/blocked/stale/no-owner work,
- labels/components for routing when state alone is insufficient,
- project documents/templates as the durable operating model,
- weekly/project-level metrics: cycle time, review bounce rate, validation failures, stale active work,
  blocked time, and reopened/rework count.

## Implementation sequence for Configure Linear

1. **Inventory rzpONE workspace**
   - teams, states, labels, project templates, issue templates, automations, members.

2. **Decide the state machine**
   - keep the branch/PR-driven path: `Todo -> Active -> Review -> Approved -> Done`.
   - document the exact branch naming regex that triggers `Todo -> Active`.
   - document `Triage` as the Linear-agent review lane for related issues, duplicates, labels,
     assignees, and relationships.
   - document when `Backlog` is non-active/scheduled-later work.

3. **Create project and issue templates**
   - project template first, then research/implementation/review/ops templates.

4. **Define repo workflow contract convention**
   - decide whether `AGENTS.md` + skills is sufficient, or whether to add a thin `WORKFLOW.md`.

5. **Create views, labels, and lightweight automations**
   - ready, active, review, approved, blocked, stale, missing owner, missing validation.

6. **Pilot inside Configure Linear**
   - one research issue,
   - one template-writing issue,
   - one review/approval issue,
   - then adjust the workflow before using it for homelab migration.

7. **Promote to homelab project**
   - once Configure Linear has working states/templates/views/automation conventions, use those
     conventions for Homelab Declarative Infrastructure Migration.

## Open risks

- **Tool-shaped cargo culting.** Symphony's daemon is not the point. The point is explicit state,
  evidence, handoffs, retries, and operator visibility.
- **Branch regex fragility.** The state machine depends on branch names matching Linear's configured
  issue regex. If agents improvise branch names, the workflow silently degrades.
- **Too many Linear states.** Extra states feel useful until agents and humans disagree about what
  they mean. Keep states minimal until pain proves otherwise.
- **Unbounded agent authority.** Symphony is explicit that trust/sandbox policy is implementation
  defined. For Linear, issue templates must make allowed actions, credentials, repo scope, and
  human-approval boundaries explicit.
- **Duplicated policy.** `AGENTS.md`, skills, Linear templates, and any future `WORKFLOW.md` can drift.
  Prefer pointers and thin contracts over giant repeated prompt blobs.

## Recommended next concrete action

Use ONE-9 (`Define AI orchestration operating model`) as the first concrete Linear issue to turn into
an actionable spec. Its output should be a short operating-model document plus proposed state/template
changes for rzpONE. After that, tackle templates and automation.
