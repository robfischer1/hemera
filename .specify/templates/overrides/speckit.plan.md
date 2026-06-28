---
description: Execute the implementation planning workflow using the plan template to generate design artifacts.
handoffs: 
  - label: Create Tasks
    agent: speckit.tasks
    prompt: Break the plan into tasks
    send: true
  - label: Create Checklist
    agent: speckit.checklist
    prompt: Create a checklist for the following domain...
scripts:
  sh: scripts/bash/setup-plan.sh --json
  ps: scripts/powershell/setup-plan.ps1 -Json
---

## User Input

```text
$ARGUMENTS
```

You **MUST** consider the user input before proceeding (if not empty).

## Planning Context — authoritative design substrate (Forge override)

The User Input above may carry a **planning-context block** handed down from an
upstream `/design` master-plan feature-node — the analytical tail below a fence
that reads `--- planning context (for /plan + reconcile, NOT /specify) ---`. When
present, it contains some or all of:

- **Scope** — decided acceptance (Given/When/Then or system-level).
- **Inter-feature seams** — Exposes / Consumes entries with named shapes + gap-state.
- **Shared-data-model slice** — the tables/fields/schemas this feature reads or writes.
- **Touches (RR)** — field-level Resource-Reach pointers (real, resolved repo paths).
- **Prerequisites** — the upstream features/DAG edges.
- **Decisions-slice** — the in-scope subset of the master-plan Decision Log.
- **Gaps surfaced / Size basis** — open questions and the measured size tier.

**This block is AUTHORITATIVE — it is decided substrate, not a hint.** It is the
binding contract `/design` already converged. Treat every item as exactly one of:

- **decided** — the planning context licenses it → **follow it verbatim. Do NOT
  re-derive, re-decide, or "improve" it.** Reconcile it into the artifacts below.
- **open** — the planning context is silent and it matters → **surface it as a
  `NEEDS CLARIFICATION` / `[OPEN]` item. Never resolve it by inventing.**

There is **no third "use judgment" state.** Where the planning context and the
spec disagree, the planning context wins (it is the later, converged decision);
note the divergence in Open & risk rather than silently reconciling.

When the User Input contains **no** planning-context block, fall back to the
standard generate-from-spec behavior unchanged.

## Pre-Execution Checks

**Check for extension hooks (before planning)**:
- Check if `.specify/extensions.yml` exists in the project root.
- If it exists, read it and look for entries under the `hooks.before_plan` key
- If the YAML cannot be parsed or is invalid, skip hook checking silently and continue normally
- Filter out hooks where `enabled` is explicitly `false`. Treat hooks without an `enabled` field as enabled by default.
- For each remaining hook, do **not** attempt to interpret or evaluate hook `condition` expressions:
  - If the hook has no `condition` field, or it is null/empty, treat the hook as executable
  - If the hook defines a non-empty `condition`, skip the hook and leave condition evaluation to the HookExecutor implementation
- For each executable hook, output the following based on its `optional` flag:
  - **Optional hook** (`optional: true`):
    ```
    ## Extension Hooks

    **Optional Pre-Hook**: {extension}
    Command: `/{command}`
    Description: {description}

    Prompt: {prompt}
    To execute: `/{command}`
    ```
  - **Mandatory hook** (`optional: false`):
    ```
    ## Extension Hooks

    **Automatic Pre-Hook**: {extension}
    Executing: `/{command}`
    EXECUTE_COMMAND: {command}

    Wait for the result of the hook command before proceeding to the Outline.
    ```
- If no hooks are registered or `.specify/extensions.yml` does not exist, skip silently

## Outline

1. **Setup**: Run `{SCRIPT}` from repo root and parse JSON for FEATURE_SPEC, IMPL_PLAN, SPECS_DIR, BRANCH. For single quotes in args like "I'm Groot", use escape syntax: e.g 'I'\''m Groot' (or double-quote if possible: "I'm Groot").

2. **Load context**: Read FEATURE_SPEC and `/memory/constitution.md`. Load IMPL_PLAN template (already copied). **If a planning-context block is present in the User Input, load it as the authoritative design substrate per the Planning Context section above.**

3. **Execute plan workflow**: Follow the structure in IMPL_PLAN template to:
   - Fill Technical Context (mark unknowns as "NEEDS CLARIFICATION") — **prefer the planning context's decided values; mark NEEDS CLARIFICATION only where it is genuinely silent.**
   - Fill Constitution Check section from constitution
   - Evaluate gates (ERROR if violations unjustified)
   - Phase 0: Generate research.md (resolve all NEEDS CLARIFICATION) — **a question the planning context already decides is NOT an unknown; do not re-research it.**
   - Phase 1: **Reconcile** the planning context into data-model.md, contracts/, quickstart.md (regenerate from the spec only where the planning context is silent)
   - Phase 1: Update agent context by running the agent script
   - Re-evaluate Constitution Check post-design

## Mandatory Post-Execution Hooks

**You MUST complete this section before reporting completion to the user.**

Check if `.specify/extensions.yml` exists in the project root.
- If it does not exist, or no hooks are registered under `hooks.after_plan`, skip to the Completion Report.
- If it exists, read it and look for entries under the `hooks.after_plan` key.
- If the YAML cannot be parsed or is invalid, skip hook checking silently and continue to the Completion Report.
- Filter out hooks where `enabled` is explicitly `false`. Treat hooks without an `enabled` field as enabled by default.
- For each remaining hook, do **not** attempt to interpret or evaluate hook `condition` expressions:
  - If the hook has no `condition` field, or it is null/empty, treat the hook as executable
  - If the hook defines a non-empty `condition`, skip the hook and leave condition evaluation to the HookExecutor implementation
- For each executable hook, output the following based on its `optional` flag:
  - **Mandatory hook** (`optional: false`) — **You MUST emit `EXECUTE_COMMAND:` for each mandatory hook**:
    ```
    ## Extension Hooks

    **Automatic Hook**: {extension}
    Executing: `/{command}`
    EXECUTE_COMMAND: {command}
    ```
  - **Optional hook** (`optional: true`):
    ```
    ## Extension Hooks

    **Optional Hook**: {extension}
    Command: `/{command}`
    Description: {description}

    Prompt: {prompt}
    To execute: `/{command}`
    ```

## Completion Report

Command ends after Phase 2 planning. Report branch, IMPL_PLAN path, and generated artifacts. **When a planning-context block was consumed, report a one-line reconcile summary: which artifacts were taken verbatim from the planning context, which were generated from the spec (silent areas), and any divergences surfaced to Open & risk.**

## Phases

### Phase 0: Outline & Research

1. **Extract unknowns from Technical Context** above:
   - For each NEEDS CLARIFICATION → research task
   - For each dependency → best practices task
   - For each integration → patterns task
   - **A point the planning context already decides is NOT an unknown — skip it.**

2. **Generate and dispatch research agents**:

   ```text
   For each unknown in Technical Context:
     Task: "Research {unknown} for {feature context}"
   For each technology choice:
     Task: "Find best practices for {tech} in {domain}"
   ```

3. **Consolidate findings** in `research.md` using format:
   - Decision: [what was chosen]
   - Rationale: [why chosen]
   - Alternatives considered: [what else evaluated]

**Output**: research.md with all NEEDS CLARIFICATION resolved

### Phase 1: Design & Contracts

**Prerequisites:** `research.md` complete

> **Reconcile-first (Forge override).** When a planning-context block is present,
> the artifacts below are **reconciled from it, not regenerated from the spec.**
> The spec seeds intent; the planning context is the decided answer-key. Pull each
> entity, seam, and pointer through **verbatim**; only fill from the spec where the
> planning context is silent; surface any conflict as `[OPEN]` in Open & risk.

1. **Populate `data-model.md`** — **from the planning context's Shared-data-model
   slice when present** (its tables/fields/schemas/access are authoritative; carry
   them verbatim). Extract entities from the feature spec **only for parts the slice
   does not cover.** Include:
   - Entity name, fields, relationships
   - Validation rules from requirements
   - State transitions if applicable

2. **Define interface contracts** (if project has external interfaces) → `/contracts/`:
   - **When the planning context's Inter-feature seams (Exposes / Consumes) are
     present, the named shapes there are the contracts — write them verbatim, do not
     invent or rename.** Use the spec only to fill genuinely-uncovered surfaces.
   - Identify what interfaces the project exposes to users or other systems
   - Document the contract format appropriate for the project type
   - Examples: public APIs for libraries, command schemas for CLI tools, endpoints for web services, grammars for parsers, UI contracts for applications
   - Skip if project is purely internal (build scripts, one-off tools, etc.)

3. **Create quickstart validation guide** → `quickstart.md`:
   - Document runnable validation scenarios that prove the feature works end-to-end
   - Include prerequisites, setup commands, test/run commands, and expected outcomes
   - Use links or references to contracts and data model details instead of duplicating them
   - Do not include full implementation code, model/service/controller bodies, migrations, or complete test suites
   - Keep this artifact as a validation/run guide; implementation details belong in `tasks.md` and the implementation phase

4. **Agent context update**:
   - Update the plan reference between the `<!-- SPECKIT START -->` and `<!-- SPECKIT END -->` markers in `__CONTEXT_FILE__` to point to the plan file created in step 1 (the IMPL_PLAN path)

**Output**: data-model.md, /contracts/*, quickstart.md, updated agent context file

## Key rules

- Use absolute paths for filesystem operations; use project-relative paths for references in documentation and agent context files
- ERROR on gate failures or unresolved clarifications
- **When a planning-context block is present, reconcile-don't-regenerate is a hard rule, not a preference: the planning context is the decided contract; the spec is the intent it was derived from. Never overwrite a decided value with a freshly-invented one.**

## Done When

- [ ] Plan workflow executed and design artifacts generated
- [ ] **Planning-context block (when present) reconciled into data-model.md / contracts/ verbatim; spec-generation used only for silent areas; divergences surfaced to Open & risk**
- [ ] Extension hooks dispatched or skipped according to the rules in Mandatory Post-Execution Hooks above
- [ ] Completion reported to user with branch, plan path, and generated artifacts
