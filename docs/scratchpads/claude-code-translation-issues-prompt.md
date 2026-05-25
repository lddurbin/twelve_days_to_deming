# Claude Code Prompt — Create GitHub Issues for the EN→FR Translation Pipeline

> Paste everything below the line into Claude Code from the root of the target repository.
> First edit the **CONFIGURATION** block so the issues are generated for your actual setup.

---

## CONFIGURATION — edit these before running

- **TARGET_VARIANT**: `French (France)`  _(alternatives: `French (Québec)`, `French (Belgium)`, `French (Switzerland)`)_
- **REGISTER**: `vous (formal)`  _(alternative: `tu (informal)` — only for younger-learner or deliberately informal courses)_
- **SUBJECT_DOMAIN**: `<e.g. data analytics / statistics / software engineering>`
- **SOURCE_LOCATION**: `<path or glob for the English source files, e.g. ./source/**/*.md>`
- **GITHUB_REPO**: `<owner/repo, or leave blank to use the current repo>`

---

## Your task

You are setting up the project tracking for an English→French translation pipeline for **technical teaching materials**. Create a complete set of GitHub issues that breaks this work into discrete, well-scoped, dependency-ordered tasks.

The pipeline's design philosophy — reflect this in the issues:
- **Glossary-first.** A validated bilingual termbase is built *before* bulk translation, so technical terms render identically everywhere. This is the single highest-leverage step.
- **Ensemble for divergence detection, not averaging.** Multiple engines (DeepL, Google Translate, and 2–3 LLMs) translate independently; the value is in surfacing *where they disagree*, not in blending them.
- **Human effort is spent adjudicating, not translating.** The reviewer validates a glossary and resolves a flagged shortlist of contested decisions — not the full text.
- **Register and variant are pinned constraints**, not left to engine drift.

### How to create the issues

1. First create the labels listed below (use `gh label create`, ignore "already exists" errors).
2. Create one **milestone** named `EN→FR Translation Pipeline v1`.
3. Create the issues **in the order given** so that issue numbers line up with the `Depends on` references. After creating each issue, note its returned number and substitute it into later `Depends on:` lines (replace the `#TERM_EXTRACTION` style placeholders with the real `#<n>`).
4. Use `gh issue create` with `--title`, `--body`, `--label`, and `--milestone`. Put the full body (context, scope, acceptance criteria, dependencies) in `--body`.
5. After creating everything, print a summary table: issue number, title, labels, dependencies.

### Labels to create

- `pipeline` — core pipeline component (colour `1d76db`)
- `setup` — scaffolding/config (colour `c2e0c6`)
- `human-review` — requires a native-speaker action (colour `d93f0b`)
- `quality` — verification/consistency (colour `fbca04`)

---

## Issues to create

Each issue below specifies its title, body content, labels, and dependencies. Expand the **Context** into a short paragraph in the issue body; keep **Scope** and **Acceptance Criteria** as checklists.

---

### Issue 1 — Repository scaffold & pipeline configuration
**Labels:** `setup`
**Depends on:** none

**Context:** Establish the directory structure, configuration, and dependency setup the rest of the pipeline relies on. Configuration values (variant, register, domain, engine list) must live in one place so every downstream step reads the same constraints.

**Scope:**
- Create directory structure: `source/`, `glossary/`, `translations/raw/`, `translations/synthesised/`, `reports/`, `config/`.
- Create `config/pipeline.yaml` capturing: target variant, register (tu/vous), subject domain, source glob, and the list of engines to use.
- Add `.env.example` listing required secrets (`DEEPL_API_KEY`, `GOOGLE_TRANSLATE_KEY`, `ANTHROPIC_API_KEY`, plus any other LLM keys); ensure `.env` is git-ignored.
- Add a `README.md` documenting the pipeline stages and how to run each.
- Pin dependencies (e.g. a `requirements.txt` or `package.json`).

**Acceptance Criteria:**
- [ ] `config/pipeline.yaml` exists and is read by at least a stub script that prints the resolved config.
- [ ] `.env` is git-ignored; `.env.example` lists every required key with no real secrets committed.
- [ ] Directory structure exists and is documented in `README.md`.
- [ ] A fresh clone can install dependencies with a single documented command.

---

### Issue 2 — Term extraction from source corpus
**Labels:** `pipeline`
**Depends on:** `#REPO_SCAFFOLD`

**Context:** Scan the English source materials and extract recurring technical/domain terms that must be translated consistently. The output is a *draft* glossary, not a final one.

**Scope:**
- Script that ingests all files matching `SOURCE_LOCATION`.
- Identify candidate terms: domain terminology, recurring multi-word phrases, acronyms, and any term appearing above a configurable frequency threshold.
- For each term record: the English term, frequency count, and example sentence(s) for context.
- Produce a candidate French rendering for each term (via one LLM call, using the configured variant/domain).
- Flag terms needing a human decision (translate / keep English / gloss on first use) — e.g. anglicisms, brand-like terms, terms with multiple valid renderings.
- Output to `glossary/draft-glossary.csv` with columns: `term_en`, `frequency`, `context_example`, `candidate_fr`, `decision_needed` (bool), `notes`.

**Acceptance Criteria:**
- [ ] Running the script on the source corpus produces `glossary/draft-glossary.csv`.
- [ ] Every term includes a frequency count and at least one context example.
- [ ] Terms with ambiguous or contested renderings are flagged `decision_needed = true`.
- [ ] Output is sorted by frequency (descending) so high-impact terms surface first.
- [ ] Re-running is idempotent (same input → same output, no duplicate rows).

---

### Issue 3 — Glossary validation workflow (human-in-the-loop)
**Labels:** `pipeline`, `human-review`
**Depends on:** `#TERM_EXTRACTION`

**Context:** A native French speaker with domain knowledge validates the draft glossary. This is the *only* large human task, and it is bounded (review a few hundred terms, not thousands of sentences). The approved glossary becomes a hard constraint for all downstream translation.

**Scope:**
- Generate a reviewer-friendly version of the draft glossary (CSV and/or a Markdown table) with clear columns for the reviewer to fill: `approved_fr`, `decision`, `reviewer_notes`.
- Provide brief reviewer instructions: how to choose between candidates, how to mark "keep English", how to flag terms for "gloss on first use".
- Add a "lock" step that converts the reviewer-completed file into `glossary/approved-glossary.json` (the machine-readable termbase), validating that every term has an `approved_fr` or an explicit non-translation decision.
- The lock step must fail loudly if any term is left undecided.

**Acceptance Criteria:**
- [ ] A reviewer-facing file is generated with clear, fillable columns and instructions.
- [ ] The lock step produces `glossary/approved-glossary.json` only when every term has a resolved decision.
- [ ] The lock step exits non-zero and lists offending terms if any are undecided.
- [ ] `approved-glossary.json` is versioned and reusable across future translation batches.

---

### Issue 4 — Multi-engine translation with glossary injection
**Labels:** `pipeline`
**Depends on:** `#GLOSSARY_VALIDATION`

**Context:** Translate the source materials through several independent engines. The approved glossary is injected as a hard constraint, the register is pinned, and the variant is specified — for every engine and every prompt.

**Scope:**
- Segment the source into translatable units (sentence or paragraph level), preserving structure and any markup/code blocks so they are not translated.
- For each segment, request a translation from each configured engine:
  - DeepL and Google Translate via their APIs (use glossary features where the API supports them).
  - 2–3 LLMs via prompts that explicitly state: target variant, register (tu/vous), domain, and the relevant approved glossary terms for that segment.
- Store every candidate in `translations/raw/` keyed by source segment ID and engine name (e.g. JSON keyed by segment, with one entry per engine).
- Preserve a stable segment ID so candidates can be aligned later and so the corpus can be reassembled.

**Acceptance Criteria:**
- [ ] Each source segment has a candidate translation from every configured engine.
- [ ] Markup, code blocks, and other non-prose elements are preserved untranslated.
- [ ] LLM prompts demonstrably include the variant, register, and applicable glossary terms (visible in logged prompts).
- [ ] Output is keyed by stable segment ID so segments can be aligned and the document reassembled.
- [ ] Failures from any single engine are logged and skipped without aborting the whole run.

---

### Issue 5 — Back-translation of candidates
**Labels:** `pipeline`, `quality`
**Depends on:** `#MULTI_ENGINE_TRANSLATION`

**Context:** Round-trip each French candidate back to English as a meaning-check signal. Useful as a flag for investigation, not as proof of correctness — treat mismatches as red flags, not matches as guarantees.

**Scope:**
- For each candidate translation, produce an English back-translation.
- Compute a similarity signal between the back-translation and the original English segment (e.g. embedding similarity and/or a simple lexical overlap score).
- Store back-translations and scores alongside each candidate.

**Acceptance Criteria:**
- [ ] Every candidate has a back-translation and a similarity score recorded.
- [ ] Segments whose back-translation diverges most from the source are identifiable/sortable.
- [ ] The output clearly documents that low similarity = "investigate", not "wrong", and high similarity ≠ "verified".

---

### Issue 6 — Segment alignment & divergence detection
**Labels:** `pipeline`, `quality`
**Depends on:** `#MULTI_ENGINE_TRANSLATION`, `#BACK_TRANSLATION`

**Context:** For each source segment, align the engine candidates and classify their agreement. Divergence is the product: it tells the reviewer exactly where judgement was required. Crucially, divergence is classified by *type*.

**Scope:**
- For each segment, align all engine candidates.
- Compute an agreement measure (full agreement / partial / split).
- Classify each divergence:
  - **Glossary-term divergence** — a candidate violates the approved termbase. This is a *bug to auto-fix* (Issue 8), not a review item.
  - **Register divergence** — a candidate drifts from the pinned tu/vous choice. Also a bug to flag/fix.
  - **Prose divergence** — legitimate stylistic/interpretive difference. This is a *flag for human review*.
- Output a structured divergence record per segment with type, the competing candidates, and (where possible) a short reason for the divergence.

**Acceptance Criteria:**
- [ ] Every segment has an agreement classification.
- [ ] Each divergence is tagged as glossary / register / prose.
- [ ] Glossary- and register-type divergences are separated from prose divergences in the output.
- [ ] The structured output can be consumed directly by the synthesis step.

---

### Issue 7 — Synthesis into an annotated decision map
**Labels:** `pipeline`
**Depends on:** `#DIVERGENCE_DETECTION`

**Context:** Produce a single synthesised French draft plus an annotated record of every decision. The synthesiser does not silently pick winners on contested prose — it auto-resolves mechanical divergences and surfaces the rest. The output must not present an authoritative-looking clean translation that tempts skipping review.

**Scope:**
- For full-agreement segments, emit the agreed translation.
- For glossary/register divergences, auto-correct to the approved term/register and record the correction.
- For prose divergences, choose a best candidate *but mark the segment as flagged*, retaining the alternatives and the reason.
- Reassemble the synthesised draft into `translations/synthesised/` mirroring the source structure.
- Produce an annotation/decision log mapping each segment to: decision type, chosen rendering, alternatives, and flag status.

**Acceptance Criteria:**
- [ ] A complete synthesised French draft is produced, mirroring source file structure and preserving non-prose elements.
- [ ] Every auto-correction (glossary/register) is logged with before/after.
- [ ] Every prose-flagged segment retains its alternatives and reason in the decision log.
- [ ] The synthesised output is clearly marked as *draft pending review*, not final.

---

### Issue 8 — Corpus-wide consistency pass
**Labels:** `quality`
**Depends on:** `#SYNTHESIS`

**Context:** A mechanical sweep across *all* output files enforcing the termbase and register globally — the check a human can't do reliably and the engines won't do at all. This catches the case where two segments each got an individually-valid but mutually-inconsistent rendering.

**Scope:**
- Scan all synthesised files for adherence to `approved-glossary.json` (flag any approved term rendered differently).
- Scan for register consistency (flag tu/vous drift against the pinned choice).
- Check that any "gloss on first use" terms are actually glossed on first occurrence and not subsequently.
- Auto-fix unambiguous violations where safe; flag anything ambiguous.
- Output a consistency report to `reports/`.

**Acceptance Criteria:**
- [ ] The pass reports every glossary-term inconsistency across the whole corpus with file and location.
- [ ] Register drift is detected and reported corpus-wide.
- [ ] "Gloss on first use" rules are verified across files (not just within a file).
- [ ] Safe, unambiguous fixes are applied automatically and logged; ambiguous cases are flagged, not silently changed.

---

### Issue 9 — Reviewer report: glossary + flagged shortlist
**Labels:** `human-review`, `quality`
**Depends on:** `#SYNTHESIS`, `#CONSISTENCY_PASS`

**Context:** The final human-facing artifact. It must turn the reviewer's job into *adjudicating a targeted shortlist* rather than reading the whole translation. It must also avoid lulling the reviewer: "all engines agreed" is shown but explicitly noted as weak evidence on nuance-sensitive prose.

**Scope:**
- Generate a single report (Markdown or HTML) containing:
  - The flagged prose-divergence segments, each showing source English, the competing French candidates, the chosen rendering, and the reason for divergence.
  - Back-translation mismatches worth investigating.
  - The consistency report's ambiguous (unfixed) flags.
  - A short methodology note stating the limits: convergence ≠ correctness, ensemble engines share blind spots, and high-stakes/nuance-sensitive segments still warrant native-speaker judgement.
- Order the report so the highest-risk items appear first.

**Acceptance Criteria:**
- [ ] The report presents only items needing human judgement, not the full text.
- [ ] Each flagged item shows source, candidates, chosen rendering, and reason.
- [ ] The report includes the methodology/limits note.
- [ ] Items are prioritised by risk (flagged prose and back-translation mismatches first).
- [ ] A reviewer could complete their pass using this report plus the synthesised draft alone.

---

## After creating all issues

Print a summary table of created issues (number, title, labels, dependencies) and confirm the milestone and labels were created. Do **not** start implementing any issue — this task is issue creation only.
