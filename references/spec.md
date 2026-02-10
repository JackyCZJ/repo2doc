# repo2doc Specification

This file defines strict output standards for repository-to-document analysis.

## 1. Folder and file contract

Default output root: `Report/<ProjectName>/`

Required files:
- `00-reading-guide.md`
- `A-01-getting-started.md`
- `B-01-deep-dive.md`
- `appendix-source-index.md`

Recommended supporting files:
- `01-system-overview.md`
- `02-module-map.md`
- `03-core-flows.md`
- `04-deep-dives.md`
- `05-data-and-state.md`
- `06-runtime-and-config.md`
- `07-risks-and-techdebt.md`
- `08-optimization-roadmap.md`

## 2. Citation contract

Use source evidence format:
- `relative/path/to/file.ext:line`

Rules:
- Each key conclusion must include at least one citation.
- Prefer direct implementation evidence over comments/docstrings.
- If no direct evidence exists, label as `Assumption` and explain why.

## 3. Chapter structure contract

Use a **minimum contract + project-adaptive sections** approach.

### 3.1 Minimum contract (always required)
- `00-reading-guide.md`
- `A-01-getting-started.md` (what/install/usage/basic QA)
- `B-01-deep-dive.md` (architecture + key hard parts + key highlights)
- `appendix-source-index.md`

### 3.2 Adaptive deep-dive sections (required to be tailored)
Do **not** force the same structure for every repo.
Choose sections based on project characteristics, e.g.:
- temporal behavior (timeouts/retries/ordering)
- state machine behavior
- mechanism implementation (protocol, scheduler, plugin, cache, queue)
- mechanism flow (request lifecycle / event lifecycle / job lifecycle)

Rules:
- Include only sections with real evidence in that repository.
- Rename headings to match project terminology.
- Explicitly mark omitted sections as `Not Applicable` when expected but absent.

### 3.3 Mermaid usage
- Prefer Mermaid code blocks embedded in markdown.
- SVG generation is optional and only on explicit request.

Supporting chapters may still use this shape when applicable:
1. Objective
2. Key findings
3. Evidence map
4. Implications
5. Open questions

Keep sections concise and repository-specific.

## 4. Flow analysis contract

For each core flow include:
- Trigger (API/event/job)
- Entry point(s)
- Main path (step-by-step)
- Failure path(s)
- Side effects (DB/cache/queue/external API)
- Observability hooks
- Citations

## 5. Risk grading contract

### P0
- Security bypass, auth fail-open, data corruption, irreversible high-impact errors

### P1
- High probability reliability/performance/operability issues

### P2
- Maintainability, readability, non-critical architecture debt

For each risk item, include:
- ID (`RISK-###`)
- Severity
- Trigger condition
- Impact scope
- Evidence
- Proposed remediation
- Verification steps

## 6. Implementation-detail contract

For each key highlight/hard-part, include at least one "implementation card" with:
- `What`: one-line behavior summary
- `Where`: exact code location (`path:line`)
- `How`: 5-20 lines code snippet (or pseudo-snippet when long)
- `Why it matters`: architecture/reliability impact

Recommended markdown shape:

```markdown
#### 实现卡片：<name>
- What: ...
- Where: `packages/x/src/y.ts:123`
- Why it matters: ...

```ts
// excerpt from packages/x/src/y.ts
...
```
```

## 7. Writing quality contract

- Use precise, neutral technical language.
- Avoid generic architecture prose without repository evidence.
- Distinguish clearly between facts, inference, and assumptions.
- Keep heading IDs stable to preserve linkability.

## 8. Linkability contract

- Ensure `00-reading-guide.md` has a clickable TOC linking all chapters.
- Use stable heading names across reruns.
- Avoid renaming top-level headings unless structure changes materially.

## 9. Limitations contract

Always include a short limitations section covering:
- Unexecuted paths
- Environment gaps
- Dependency assumptions
- Untested runtime scenarios
