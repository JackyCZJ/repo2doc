---
name: repo2doc
description: Deep repository architecture analysis and evidence-based documentation generation. Use when the user provides a Git URL (or local repo path) and wants: (1) architecture/source-code deep dive, (2) module and flow analysis, (3) a detailed clickable handbook mapped to project structure, and (4) module-specific documentation files named after real modules.
---

# repo2doc

Produce a structure-mirrored, evidence-first technical handbook from a repository.

## Inputs

Collect these inputs before execution:
- Repository source: Git URL or local path
- Target revision: branch/tag/commit (default: default branch)
- Output root (default: `Report/<ProjectName>/`)
- Depth mode: `standard` or `audit`
- Language preference for output

If the repository is remote, clone it locally first.

## Workflow

### 1) Baseline and inventory

- Lock analysis revision (record branch + commit hash).
- Detect language/runtime/build entrypoints.
- Build a directory map and identify major domains/modules.
- Extract config surfaces (`.env*`, yaml/json/toml configs, CI, deployment files).

Write baseline metadata and navigation to `Report/<ProjectName>/00-reading-guide.md`.

### 2) Architecture decomposition

Analyze top-down:
- System boundary: external dependencies, service boundaries, data stores
- Layering pattern: API/application/domain/infrastructure (or equivalent)
- Runtime shape: monolith, service split, workers, jobs, schedulers
- Cross-cutting concerns: auth, logging, metrics, tracing, error handling

Write architecture output to `Report/<ProjectName>/system-overview.md`.

### 3) Flow and module deep dive

Select core user/business flows first, then trace code paths:
- Entry -> orchestration -> domain logic -> persistence/integration -> return path
- Include error paths, retries/timeouts, and failover behavior where present
- Map important modules to responsibilities and key interfaces

Write outputs to:
- `Report/<ProjectName>/module-map.md`
- `Report/<ProjectName>/core-flows.md`
- `Report/<ProjectName>/<module-name>.md` (one file per major module; use real module names, not template names)

### 4) Data and operations view

Document:
- Data models and state transitions
- Configuration hierarchy and precedence
- Startup/run/deploy behavior
- Observability points (log/metric/trace hooks)

Write outputs to:
- `Report/<ProjectName>/data-and-state.md`
- `Report/<ProjectName>/runtime-and-config.md`

### 5) Risk and improvement plan

Classify findings by severity:
- `P0`: security/correctness failures, fail-open auth, critical data integrity risk
- `P1`: high-impact stability/performance/operability issues
- `P2`: maintainability/documentation/developer-experience debt

For each finding include: trigger, impact, evidence, fix direction, verification check.

Write outputs to:
- `Report/<ProjectName>/risks-and-techdebt.md`
- `Report/<ProjectName>/optimization-roadmap.md`

### 6) Evidence index and linkability

- Add a source index with all cited files.
- Ensure every major conclusion links to source references in `path:line` format.
- Keep headings stable and anchor-friendly.

Write source index to `Report/<ProjectName>/appendix-source-index.md`.

## Documentation guidance

Use `references/spec.md` as guidance.

Default quality goals:
- Evidence-first: important claims require code/config evidence.
- Structure mirror: chapter structure follows repository layout.
- Layered readability: executive view before module details.
- Actionable findings: each risk has fix + validation guidance.
- No fluff: avoid generic text without repository-specific evidence.

## Optional quality checks

Validation is optional and should not block report generation by default.

- Scaffold: `scripts/scaffold-report.sh <ProjectName> --modules <csv>`
- Validate (warn-only default): `scripts/validate-report.sh <ProjectName>`
- Validate (strict + fail on errors): `scripts/validate-report.sh <ProjectName> --strict --enforce`

## Output checklist

Deliver all of the following:
- Full handbook files under `Report/<ProjectName>/`
- `project-overview.md` (installation, usage, basic QA)
- Module deep-dive files named by real modules (for example: `auth-service.md`, `scheduler.md`)
- Deep-dive sections must be project-adaptive (for example: state machine, temporal behavior, mechanism implementation/flow), not rigidly fixed
- Include Mermaid diagrams as embedded markdown blocks by default; do not require SVG generation unless explicitly requested
- Clickable table of contents in `00-reading-guide.md`
- Risk register with `P0/P1/P2`
- Source evidence index (`appendix-source-index.md`)
- Short “analysis limitations” note for unverified assumptions

## Escalation triggers

Call out blockers early if:
- Missing dependencies prevent static/dynamic verification
- Monorepo scope is too large for one pass
- Build scripts are non-deterministic or environment-coupled

When blocked, still ship a partial report with explicit gaps and next verification steps.
