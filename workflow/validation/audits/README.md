# Audits — what a sample of the clean text turned out to be

`results/` records what the validator found. `adjudications/` records what a
person decided about every flag it raised. Neither says anything about the text
the validator matched **cleanly**: about 2,200 paragraphs across the eighteen
records that no pass has flagged, so nobody has read them against the source
since the original conversion. This directory holds the measurement of that
population. See [#746](https://github.com/lddurbin/twelve_days_to_deming/issues/746),
Wave 3 of epic [#734](https://github.com/lddurbin/twelve_days_to_deming/issues/734).

"Matched cleanly" is a similarity score, not a verdict. A single wrong word
in a fifty-word sentence scores exactly the 0.98 threshold and classifies clean,
and emphasis is invisible to the comparator entirely. Wave 2 has found defects
of both kinds in text a person had already verified. So the claim this directory
supports has to be measured — and it is two claims, not one, because a lost
italic and a wrong word are both departures from Neave but support very
different statements about fidelity:

> Of the text the comparator calls clean, at most this share **changes what
> Neave said**, and at most this larger share **differs from him in any way**,
> each at 95% confidence.

Day 5 is why they are stated apart. Its seventeen audited paragraphs held four
real deviations — two swapped punctuation marks, two lost emphases — and not one
of them changed a word. A single rate would have published that as "at most 40%
of clean text is wrong", which is true, useless, and hides the part anyone
actually wants to know: the substantive rate was zero in seventeen.

One file per record, `day-NN.yml` or `<manifest>.yml`, named to match
`results/`. Written by `scripts/sample-audit.py reveal`, never by hand.

## The protocol

Decided in #734 on 2026-09-13: **Lee audits**, because a Claude session auditing
text Claude sessions transcribed would reproduce the same errors and report
agreement, not fidelity. The caveat that shapes everything below is that Lee is
independent of Claude but not of the process — he verified the original
conversion too. Two requirements follow, and the tool implements both.

1. **Source first, then the site, clause by clause.** The page image before the
   card, because that is the only way emphasis is in scope at all.
2. **Planted defects, blind.** Some cards display a changed version of the site
   text. The share of those the auditor catches is their measured sensitivity,
   and the bound is divided by it rather than assuming perfect detection.

### 1. Draw

```
python3 scripts/sample-audit.py draw day-05
```

This refuses unless four things are true, and says which one isn't:

- **The record's Wave 2 pass is decided** (`adjudications/<record>.json` has
  `decided_at`). An audit measures what a finished pass missed. Drawing from a
  record whose flags are still open would count defects Wave 2 is about to fix.
- **Its `results/` file is current.** Same `scorer_version` as the pipeline, same
  source PDF hash, and the classification re-derived now reproduces the recorded
  counts exactly. The population is re-derived rather than read, because a
  results file holds counts, never a list.
- **Its content and results are committed.** The record pins the commit it drew
  from.
- **It has not been audited before.** A record is drawn once. Re-drawing with a
  new seed after seeing a sample is how a sample gets chosen.

**The seed is the record's Wave 2 pass issue number**, read from its
adjudication record — Day 5's is 771. It is fixed before anyone has seen a
sample, which is the property a seed needs. `--seed` exists for a record with no
pass issue, and should be recorded somewhere public before the draw if used.

Twenty cards by default. The draw writes three files into
`workflow/validation/audit/`, which is gitignored:

| file | what | who may open it |
|---|---|---|
| `<record>.html` | the review page, built from the Wave 2 adjudication template | publish it as an Artifact |
| `<record>.sample.json` | the page's data, and what `reveal` scores against | anyone |
| `<record>.key.json` | which cards carry a plant, and what was changed | **not the auditor, until reveal** |

Nothing the draw prints, and nothing on the page, says how many cards are
planted or which.

### 2. Audit

For each card: open the page image at the cited page, find the paragraph by its
opening and closing words, read the source, then read the card's site text.

| verdict | means |
|---|---|
| **Exact** | the site says what the source says. A difference the site's own conventions account for — a heading's case, an enriched cross-reference, curly quotes — is Exact too: the site is not departing from Neave |
| **Minor** | a real difference that does not change the meaning. In practice: punctuation, or emphasis the source has and the site has lost |
| **Substantive** | a real difference that does change it — a wrong word or number, a dropped or an added one |

Minor and Substantive are both real and both get fixed. They are split only so
the two can be counted apart, and every one of either needs a note quoting both
sides.

**This rubric replaced a three-way Exact / Trivial / Defect one after Day 5,
whose middle bucket was the reason.** Labelled "Trivial" and defined as "a
difference the site's conventions account for", it read in use as "small but
real" — and took four genuine deviations *and* a planted defect that the auditor
had described correctly in the notes beside them. The old scorer counted a plant
as caught only on a Defect verdict, so a record whose auditor had found four real
problems and spotted a plant scored zero sensitivity and a bound of 1.0. A
record's `rubric:` field says which vocabulary it was audited under; Day 5 is
`exact/minor/substantive`, re-scored from the verdicts as exported, since under
the new mapping every one of them was already filed where it belonged.

Judge the card, not the live site or the `.qmd`: the planted cards differ from
both, and looking would reveal them.

The card's site text is rendered by pandoc from the source lines the comparator
matched, trimmed to the lines those sentences touch. It can run a clause past the
paragraph where the site sets two of Neave's paragraphs on one line — measured at
under 1% of the population. Where one sentence of a paragraph matched somewhere
else on the site entirely, the card names where, since that is the #645 shape
worth checking by eye.

### 3. Reveal

```
python3 scripts/sample-audit.py reveal day-05 --verdicts ~/Downloads/audit-day-05-verdicts.json
```

Scores the export against the key and writes `audits/<record>.yml`. Every card
needs a verdict, and the export must come from this draw — the page's pass name
carries a fingerprint of it.

Reveal prints each planted card whose verdict was a deviation, beside its note,
for confirmation that the note names the plant. Two flags handle the cards where
it does not, and both keep the card out of the bound either way:

| the note… | flag | effect |
|---|---|---|
| names something else entirely | `--other-defect <id>` | the plant was missed, and a real finding is recorded |
| names the plant **and** a real defect beside it | `--also-defect <id>` | the plant was caught, and a real finding is recorded |

`--also-defect` exists because Day 5's A-14 was both: the auditor named the
planted `!` exactly and, in the same note, a lost italic three clauses earlier.
Without it a real defect disappears for having shared a card with a plant.

A plant counts as **caught** on either deviation verdict — detection is what
sensitivity measures — while `severity_matched` records how often the auditor
also filed it at the right severity. The two come apart: Day 5 caught its `!`
and filed it correctly, but had the old rubric's middle bucket still meant
"Trivial" that same verdict would have scored as a miss.

**Every entry in `findings` is a real transcription defect**, Minor as much as
Substantive, and goes through the Wave 2 fix path — a cited issue and PR, like
any other.

## The record

| field | notes |
|---|---|
| `record`, `source_pdf`, `scorer_version`, `commit` | what was sampled, by which comparator, at which commit |
| `rubric` | the verdict vocabulary the auditor worked under, `exact/minor/substantive` |
| `seed`, `drawn_at`, `revealed_at`, `auditor` | who and when; the seed makes the draw reproducible |
| `population` | matched-cleanly paragraphs in the record at `commit` |
| `sample` | `cards` shown, `planted` among them, `audited` = cards − planted |
| `verdicts` | how many of each |
| `plants` | `planted`; `caught` — a deviation verdict on a planted card whose note names the plant; and `severity_matched`, how many of those were also filed at the plant's own severity |
| `bound` | two of them, `substantive` and `any_deviation` — see below |
| `findings` | real defects found, each with its `severity`, for the fix path |
| `paragraphs` | every card: page, file and lines, verdict, note, and `planted` — the key, `null` for an unplanted card |

**Reproducing a draw.** Check out `commit` and run the same draw into another
directory with `--output-dir`. Same seed, same content, same `scorer_version`
gives the same cards and the same plants: every choice ranks candidates by a
SHA-256 digest of the seed and the candidate's own text, never by `random`,
whose `sample()` and `choice()` Python does not promise to keep stable.

## The statistics

A planted card's text was altered on the page, so its verdict says nothing about
the corpus. Plants are excluded from the sample the rate is measured over:
**n = cards − planted**, 16 to 18 for a twenty-card draw.

**Two bounds over the same n.** `bound.substantive` counts only the verdicts
that change meaning; `bound.any_deviation` counts those and the Minor ones
together. Every unplanted card was read against the source whatever it turned
out to say, so both run over the same seventeen-odd paragraphs and differ only
in what counts as a defect — and in which plants measure the detection of it.

**The raw bound** (`upper`) is the exact one-sided 95% upper limit on that
rate, from `real_defects` in n (Clopper–Pearson). With no defects it is
1 − 0.05^(1/n), which the rule of three approximates as 3/n: 16.2% for n = 17.

**The adjusted bound** (`adjusted_upper`) divides that by the auditor's measured
sensitivity, p̂ = caught / planted — counted within that severity, since catching
a swapped word and catching a lost italic are different skills at different
rates. With no defects found it is about 3/(n·p̂). A defect the auditor would
have missed is not in the count, so the raw bound silently assumes p̂ = 1.

**A severity with no plants supports no claim.** Two to four plants per record
cannot cover both severities, so one of them routinely has zero, its sensitivity
is `null`, and its adjusted bound is 1.0. Day 5 drew one substantive plant and
missed it, which is why its substantive bound reads 16.2% raw and 100% adjusted:
seventeen paragraphs with no meaning-changing deviation found, and no evidence
the auditor would have seen one. Both halves of that are worth recording, and
neither is a result on its own.

**One record says little.** Seventeen paragraphs can only show that a record's
clean text is not badly wrong — a bound near 16% — and two to four plants make
p̂ a coarse estimate. The adjustment is a point correction: it does not carry the
uncertainty in p̂ itself. Day 5 on its own establishes almost nothing; what it
establishes about the *instrument* is most of what it was worth.

**The headline is corpus-wide.** Pooled over all eighteen records, roughly 300
audited paragraphs with none found defective bound the escape rate at about 1%
at 95% confidence if detection were perfect, and the 30–60 plants pooled with
them estimate p̂ well enough to divide by. The published claim is the pooled
3/(n·p̂), stated with that caveat and with what it does not cover:

- **Flagged text** is not in this population; its evidence is the adjudication
  records.
- **Figures and tables as images** are out of scope, owned by #725.
- **Plants approximate real defects**, drawn from the classes Wave 2 found — word
  substitutions, dropped and inserted words, one wrong digit, a dropped or added
  `!`, lost emphasis — but a planted change may be easier or harder to see than
  a natural one.
- **Minor is a floor, not a census.** An auditor reading for meaning will catch
  every wrong word but skim past some punctuation, so the any-deviation rate is
  the more under-measured of the two, and its p̂ is what corrects for that.
