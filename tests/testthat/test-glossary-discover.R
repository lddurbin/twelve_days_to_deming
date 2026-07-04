# --- discover un-seeded candidate terms (issue #415) ---
#
# Acceptance criteria under test:
#   * No seed term (or alias) reappears as a discovered candidate.
#   * Every candidate is flagged decision_needed = TRUE with an empty
#     fr_rendering.
#   * The frequency threshold is configurable.
#
# Plus coverage for the individual mining strategies (bigram, trigram,
# capitalised-phrase, exact-repeat UI label) and determinism, matching the
# testing discipline set by test-glossary-corpus.R.

source(here::here("R/translation/glossary-discover.R"))

repo_root <- here::here()

#' Build a minimal segments data.frame matching glossary_segments()'s schema.
.mk_segments <- function(text, kind = "prose", file = "test.qmd") {
  n <- length(text)
  data.frame(
    text = text,
    kind = rep(kind, length.out = n),
    occurrence_type = rep(ifelse(kind == "prose", "prose", "ui"), length.out = n),
    file = rep(file, length.out = n),
    start_line = seq_len(n),
    stringsAsFactors = FALSE
  )
}

#' Build a minimal seed data.frame matching seed-terms.csv's schema.
.mk_seed <- function(term_en, aliases, fr_rendering = "x", source = "test", decision_needed = FALSE) {
  n <- length(term_en)
  data.frame(
    term_en = term_en, fr_rendering = rep(fr_rendering, n), source = rep(source, n),
    aliases = aliases, decision_needed = rep(decision_needed, n),
    stringsAsFactors = FALSE
  )
}

# ---------------------------------------------------------------------------
# 1. Seed exclusion (AC1) — the core, most important guarantee.
# ---------------------------------------------------------------------------

test_that("a seeded term does not reappear as a discovered candidate", {
  seed <- .mk_seed("common-cause", "common cause|common-cause variation")
  segments <- .mk_segments(rep(
    "Deming taught us that common cause variation matters a great deal in practice.", 6
  ))

  cand <- discover_candidates(segments, seed, min_freq = 3)

  expect_false("common cause" %in% tolower(cand$term_en))
})

test_that("seed exclusion matches regardless of hyphenation or case", {
  # term_en is a kebab slug; the corpus mentions the Title Case alias form.
  seed <- .mk_seed("system-of-profound-knowledge", "System of Profound Knowledge|SoPK")
  segments <- .mk_segments(rep(
    "Every part of the System of Profound Knowledge reinforces the others.", 6
  ))

  cand <- discover_candidates(segments, seed, min_freq = 3)

  expect_false("system of profound knowledge" %in% tolower(cand$term_en))
})

test_that("a genuinely new recurring phrase is still discovered alongside an excluded seed term", {
  seed <- .mk_seed("common-cause", "common cause")
  segments <- .mk_segments(c(
    rep("Deming taught us that common cause variation matters in practice.", 6),
    rep("The Widget Assembly Protocol was reviewed again this week.", 6)
  ))

  cand <- discover_candidates(segments, seed, min_freq = 5)

  expect_false("common cause" %in% tolower(cand$term_en))
  expect_true("widget assembly protocol" %in% tolower(cand$term_en))
})

# ---------------------------------------------------------------------------
# 1b. Curated non-terminological exclusions (glossary/discovery-exclusions.csv).
# ---------------------------------------------------------------------------

#' Build a minimal exclusions data.frame matching discovery-exclusions.csv's schema.
.mk_exclusions <- function(term_en) {
  data.frame(term_en = term_en, reason = rep("test", length(term_en)), stringsAsFactors = FALSE)
}

test_that("a curated exclusion does not reappear as a discovered candidate", {
  seed <- .mk_seed(character(0), character(0))
  segments <- .mk_segments(rep("He told me the results a long while ago.", 5))
  exclusions <- .mk_exclusions("told me")

  cand <- discover_candidates(segments, seed, min_freq = 4, exclusions = exclusions)

  expect_false("told me" %in% tolower(cand$term_en))
})

test_that("exclusion matching is case- and hyphen-insensitive, like seed exclusion", {
  seed <- .mk_seed(character(0), character(0))
  segments <- .mk_segments(rep("Effective decision-making relies on good data every time.", 5))
  exclusions <- .mk_exclusions("Decision Making")

  cand <- discover_candidates(segments, seed, min_freq = 4, exclusions = exclusions)

  expect_false("decision making" %in% tolower(cand$term_en))
})

test_that("a candidate not in the exclusion list is still discovered", {
  seed <- .mk_seed(character(0), character(0))
  segments <- .mk_segments(rep("Please inspect the control chart before the next shift.", 5))
  exclusions <- .mk_exclusions("told me")

  cand <- discover_candidates(segments, seed, min_freq = 4, exclusions = exclusions)

  expect_true("control chart" %in% tolower(cand$term_en))
})

test_that("a NULL or empty exclusions argument behaves exactly like the default", {
  seed <- .mk_seed(character(0), character(0))
  segments <- .mk_segments(rep("Please inspect the control chart before the next shift.", 5))

  a <- discover_candidates(segments, seed, min_freq = 4)
  b <- discover_candidates(segments, seed, min_freq = 4, exclusions = NULL)
  c <- discover_candidates(segments, seed, min_freq = 4, exclusions = .mk_exclusions(character(0)))

  expect_identical(a, b)
  expect_identical(a, c)
})

# ---------------------------------------------------------------------------
# 2. Every candidate: decision_needed = TRUE, blank fr_rendering (AC2).
# ---------------------------------------------------------------------------

test_that("every candidate has decision_needed = TRUE and NA fr_rendering/source", {
  seed <- .mk_seed(character(0), character(0))
  segments <- .mk_segments(rep("The Widget Assembly Protocol was reviewed again this week.", 5))

  cand <- discover_candidates(segments, seed, min_freq = 3)

  expect_true(nrow(cand) > 0)
  expect_true(all(cand$decision_needed))
  expect_true(all(is.na(cand$fr_rendering)))
  expect_true(all(is.na(cand$source)))
})

# ---------------------------------------------------------------------------
# 3. min_freq is configurable (AC3).
# ---------------------------------------------------------------------------

test_that("min_freq controls which candidates survive", {
  seed <- .mk_seed(character(0), character(0))
  segments <- .mk_segments(rep("The Widget Assembly Protocol was reviewed again.", 4))

  below <- discover_candidates(segments, seed, min_freq = 5)
  at    <- discover_candidates(segments, seed, min_freq = 4)

  expect_false("widget assembly protocol" %in% tolower(below$term_en))
  expect_true("widget assembly protocol" %in% tolower(at$term_en))
})

# ---------------------------------------------------------------------------
# 4. Individual mining strategies.
# ---------------------------------------------------------------------------

test_that("a recurring bigram of content words is discovered", {
  seed <- .mk_seed(character(0), character(0))
  segments <- .mk_segments(rep("Please inspect the control chart before the next shift.", 5))

  cand <- discover_candidates(segments, seed, min_freq = 4)

  expect_true("control chart" %in% tolower(cand$term_en))
})

test_that("bigrams where every token is a stopword are never candidates", {
  seed <- .mk_seed(character(0), character(0))
  segments <- .mk_segments(rep("This happens because of the way that it is used, and of that.", 8))

  cand <- discover_candidates(segments, seed, min_freq = 3)

  expect_false("of the" %in% tolower(cand$term_en))
  expect_false("and of" %in% tolower(cand$term_en))
})

test_that("a recurring trigram of content words is discovered", {
  seed <- .mk_seed(character(0), character(0))
  segments <- .mk_segments(rep("The central limit theorem underpins a lot of this reasoning.", 5))

  cand <- discover_candidates(segments, seed, min_freq = 4)

  expect_true("central limit theorem" %in% tolower(cand$term_en))
})

test_that("a 4+ word capitalised-phrase run is discovered as one candidate, not fragments", {
  seed <- .mk_seed(character(0), character(0))
  segments <- .mk_segments(rep(
    "Please review the Total Process Improvement Board before Friday.", 5
  ))

  cand <- discover_candidates(segments, seed, min_freq = 4)

  expect_true("total process improvement board" %in% tolower(cand$term_en))
})

test_that("a 4+ word capitalised phrase containing a connector word survives end-to-end", {
  # Regression test: the stopword/length guard must apply only to plain
  # bigram/trigram candidates. .cap_phrases() output containing a connector
  # word (e.g. the "of" in "System of Profound Knowledge" — the canonical
  # example this whole mechanism exists for) was previously being run
  # through the SAME guard and silently discarded, because "of" is a
  # stopword. .cap_phrases() itself returned the phrase correctly; it was
  # discover_candidates() that dropped it before it ever reached the
  # frequency count.
  seed <- .mk_seed(character(0), character(0))
  segments <- .mk_segments(rep(
    "Deming described the System of Profound Knowledge in his final book.", 5
  ))

  cand <- discover_candidates(segments, seed, min_freq = 4)

  expect_true("system of profound knowledge" %in% tolower(cand$term_en))
})

test_that("a capitalised phrase exactly bigram/trigram length is counted once, not doubled", {
  # "Optional Extras" is capitalised AND exactly 2 tokens long, so it is
  # reachable by both the plain bigram window and capitalised-phrase
  # detection. Each of the 5 occurrences below must contribute frequency 1,
  # not 2 (regression test for the double-count this design deliberately
  # avoids — see .cap_phrases()'s length >= 4 cutoff).
  seed <- .mk_seed(character(0), character(0))
  segments <- .mk_segments(rep("Please refer to the Optional Extras for more detail.", 5))

  cand <- discover_candidates(segments, seed, min_freq = 4)
  row <- cand[tolower(cand$term_en) == "optional extras", ]

  expect_equal(nrow(row), 1L)
  expect_equal(row$frequency, 5L)
})

test_that("an exact-repeat UI/ARIA label is discovered", {
  seed <- .mk_seed(character(0), character(0))
  segments <- .mk_segments(
    rep("Type your comments here.", 5),
    kind = "ui-string"
  )

  cand <- discover_candidates(segments, seed, min_freq = 4)

  expect_true("type your comments here." %in% tolower(cand$term_en))
  expect_equal(cand$occurrence_types[tolower(cand$term_en) == "type your comments here."], "ui")
})

test_that("contexts is NA, not empty string, when no non-empty snippet survives", {
  # A ui-string/aria-label candidate's context is its source file path; an
  # empty file path leaves zero non-empty samples. contexts must match the
  # NA_character_ convention already used by fr_rendering/source, not fall
  # back to paste()'s "" on an empty vector.
  seed <- .mk_seed(character(0), character(0))
  segments <- .mk_segments(rep("Thought", 5), kind = "aria-label", file = "")

  cand <- discover_candidates(segments, seed, min_freq = 4)
  row <- cand[tolower(cand$term_en) == "thought", ]

  expect_equal(nrow(row), 1L)
  expect_true(is.na(row$contexts))
})

test_that("term_en uses the most frequent surface casing, not whichever occurred first", {
  # "Control Chart" (capitalised) appears first in corpus order but only 3
  # times; "control chart" (lowercase) appears later but 7 times. The more
  # frequent casing must win, not the first-seen one.
  segments <- rbind(
    .mk_segments(rep("Control Chart review happens weekly for teams.", 3)),
    .mk_segments(rep("Please inspect the control chart before shipping.", 7))
  )
  seed <- .mk_seed(character(0), character(0))

  cand <- discover_candidates(segments, seed, min_freq = 4)
  row <- cand[tolower(cand$term_en) == "control chart", ]

  expect_equal(nrow(row), 1L)
  expect_identical(row$term_en, "control chart")
  expect_equal(row$frequency, 10L)
})

test_that("occurrence_types aggregates across prose and ui surfaces for the same term", {
  seed <- .mk_seed(character(0), character(0))
  segments <- rbind(
    .mk_segments(rep("Please review the Technical Aid before you begin.", 4)),
    .mk_segments(rep("Technical Aid", 4), kind = "aria-label")
  )

  cand <- discover_candidates(segments, seed, min_freq = 4)
  row <- cand[tolower(cand$term_en) == "technical aid", ]

  expect_equal(nrow(row), 1L)
  expect_equal(row$occurrence_types, "prose|ui")
  expect_equal(row$frequency, 8L)
})

# ---------------------------------------------------------------------------
# 5. .cap_phrases() unit tests (direct, not routed through discover_candidates).
# ---------------------------------------------------------------------------

test_that(".cap_phrases truncates a run that ends on a dangling connector", {
  # "Board of directors" — "of" is a connector word, but nothing capitalised
  # follows it, so it must be dropped rather than swept into the run.
  toks <- .tokenize_prose("Deming introduced the Total Quality Improvement Board of directors last year.")

  expect_identical(.cap_phrases(toks), "Total Quality Improvement Board")
})

test_that(".cap_phrases includes a connector only when another capitalised token follows it", {
  toks <- .tokenize_prose("Deming's own System of Profound Knowledge evolved over decades.")

  expect_identical(.cap_phrases(toks), "System of Profound Knowledge")
})

test_that(".cap_phrases never emits a run shorter than 4 tokens", {
  toks <- .tokenize_prose("The Optional Extras section covers six sigma.")

  expect_identical(.cap_phrases(toks), character(0))
})

test_that(".cap_phrases drops a run longer than max_len wholesale, not truncated", {
  # Pinning intentional behaviour: a run > max_len is skipped entirely rather
  # than emitting a max_len-length prefix. Real-corpus long runs are almost
  # always bibliography citations or heading concatenations, so a truncated
  # fragment would be misleading rather than useful (see the comment at the
  # length check in .cap_phrases()).
  toks <- .tokenize_prose(
    "Deming Wheeler Shewhart Juran Ishikawa Crosby Feigenbaum improved quality together."
  )

  expect_identical(.cap_phrases(toks), character(0))
})

# ---------------------------------------------------------------------------
# 5b. Nested-duplicate suppression.
# ---------------------------------------------------------------------------

test_that("a bigram that never occurs outside a longer trigram is dropped", {
  # Every occurrence of "Beads Experiment" here is immediately preceded by
  # "Red", so the two candidates end up with identical frequency -- the
  # bigram is never an independent term in this corpus. ("We now recall the"
  # keeps the capitalised run from starting at the sentence-initial word, so
  # this is genuinely a plain trigram/bigram pair, not a .cap_phrases() run.)
  seed <- .mk_seed(character(0), character(0))
  segments <- .mk_segments(rep("We now recall the Red Beads Experiment from earlier.", 6))

  cand <- discover_candidates(segments, seed, min_freq = 4)

  expect_true("red beads experiment" %in% tolower(cand$term_en))
  expect_false("beads experiment" %in% tolower(cand$term_en))
})

test_that("a shorter candidate is kept when it also recurs outside the longer one", {
  seed <- .mk_seed(character(0), character(0))
  segments <- .mk_segments(c(
    rep("We now recall the Red Beads Experiment from earlier.", 6),
    rep("Later the Beads Experiment was repeated differently.", 3)
  ))

  cand <- discover_candidates(segments, seed, min_freq = 4)

  expect_true("red beads experiment" %in% tolower(cand$term_en))
  row <- cand[tolower(cand$term_en) == "beads experiment", ]
  expect_equal(nrow(row), 1L)
  expect_equal(row$frequency, 9L)
})

test_that("a plural is never treated as containing its singular", {
  # "Technical Aid" must not be dropped as if it were "contained" in
  # "Technical Aids" merely because one string prefixes the other --
  # matching requires a boundary, not a bare substring search. Each form
  # recurs across two DIFFERENT trailing words so neither's total frequency
  # ties any single trigram's -- otherwise the bigram itself would be
  # (correctly) dropped as fully nested in one specific trigram context,
  # which isn't what this test is checking.
  seed <- .mk_seed(character(0), character(0))
  segments <- .mk_segments(c(
    rep("The Technical Aid section covers this rule.", 3),
    rep("We reviewed the Technical Aid resource yesterday.", 2),
    rep("Several Technical Aids cover this material.", 3),
    rep("Additional Technical Aids exist elsewhere.", 2)
  ))

  cand <- discover_candidates(segments, seed, min_freq = 4)

  expect_true("technical aid" %in% tolower(cand$term_en))
  expect_true("technical aids" %in% tolower(cand$term_en))
})

test_that("ordinary lower-case vocabulary is never dropped, even if always followed by the same word", {
  # "control chart" here is always immediately followed by "before", so the
  # trigram "control chart before" ties its frequency exactly -- but
  # ordinary vocabulary must never be treated as a nested duplicate just
  # because a small corpus happens to repeat the same next word every time.
  seed <- .mk_seed(character(0), character(0))
  segments <- .mk_segments(rep("Please inspect the control chart before the next shift.", 5))

  cand <- discover_candidates(segments, seed, min_freq = 4)

  expect_true("control chart" %in% tolower(cand$term_en))
})

test_that("a capitalised phrase is not swallowed by a sentence-initial article artifact", {
  # .cap_phrases() can't tell a sentence-initial "The" from a genuine
  # proper-noun-initial capital, so "The Widget Assembly Protocol" (a
  # .cap_phrases() run) and "Widget Assembly Protocol" (the plain trigram)
  # tie in frequency here. The former's only extra token is the article
  # "The" -- capitalisation noise, not a real named-entity expansion -- so
  # the latter, more useful candidate must survive.
  seed <- .mk_seed(character(0), character(0))
  segments <- .mk_segments(rep("The Widget Assembly Protocol was reviewed again.", 4))

  cand <- discover_candidates(segments, seed, min_freq = 4)

  expect_true("widget assembly protocol" %in% tolower(cand$term_en))
})

test_that("a name is never treated as containing its own possessive form", {
  # .tokenize_plain() treats an apostrophe as part of the same word, so
  # "Scherkenbach's" is one token, not "Scherkenbach" + "'s" -- "Bill
  # Scherkenbach" must not be dropped as if it were "contained" in "Bill
  # Scherkenbach's" merely because the apostrophe reads as a boundary. Each
  # form recurs across two different trailing words so neither's total
  # frequency ties any single trigram's (see the "Technical Aid"/"Technical
  # Aids" test above for why that variation matters here).
  seed <- .mk_seed(character(0), character(0))
  segments <- .mk_segments(c(
    rep("We recall what Bill Scherkenbach taught us in Detroit.", 2),
    rep("History remembers how Bill Scherkenbach guided the team.", 2),
    rep("Later, Bill Scherkenbach's guidance proved essential.", 2),
    rep("Indeed, Bill Scherkenbach's insight helped everyone.", 2)
  ))

  cand <- discover_candidates(segments, seed, min_freq = 4)

  expect_true("bill scherkenbach" %in% tolower(cand$term_en))
  expect_true("bill scherkenbach's" %in% tolower(cand$term_en))
})

test_that("nested-duplicate suppression on the real corpus never drops an independently-recurring term", {
  segments <- glossary_segments(repo_root)
  seed <- read.csv(file.path(repo_root, "glossary", "seed-terms.csv"), stringsAsFactors = FALSE)

  cand <- discover_candidates(segments, seed, min_freq = 10)

  # "control chart" recurs far more often on its own than inside any longer
  # phrase containing it; suppression must never remove a term this common.
  expect_true("control chart" %in% tolower(cand$term_en))
})

# ---------------------------------------------------------------------------
# 5c. False adjacency across a stripped digit/punctuation gap.
# ---------------------------------------------------------------------------

test_that(".tokenize_bridged inserts a break where a digit/punctuation gap was stripped", {
  # .tokenize_plain()'s regex only ever matches letter runs, so " 10. "
  # between "Point" and "Eliminate" simply vanishes -- .tokenize_bridged()
  # must mark that gap with NA instead of letting the words end up adjacent.
  toks <- .tokenize_bridged("Point 10. Eliminate exhortations now.")

  expect_true(is.na(toks[2]))
  expect_identical(toks[-2], c("Point", "Eliminate", "exhortations", "now"))
})

test_that(".tokenize_bridged does not break on an ordinary whitespace-only gap", {
  toks <- .tokenize_bridged("Eliminate exhortations now.")

  expect_false(anyNA(toks))
  expect_identical(toks, c("Eliminate", "exhortations", "now"))
})

test_that(".tokenize_bridged treats a bare hyphen as bridgeable, not a break", {
  # .norm_term() already treats "common-cause" and "common cause" as the same
  # term, so a hyphenated compound must tokenise adjacently like the
  # space-separated form does -- it must NOT be mistaken for a stripped-digit
  # gap the way "Point 10. Eliminate" is.
  toks <- .tokenize_bridged("Effective decision-making relies on data.")

  expect_false(anyNA(toks))
  expect_identical(toks, c("Effective", "decision", "making", "relies", "on", "data"))
})

test_that("a hyphenated compound is still discovered as a bigram end-to-end", {
  seed <- .mk_seed(character(0), character(0))
  segments <- .mk_segments(rep("Effective decision-making relies on good data every time.", 5))

  cand <- discover_candidates(segments, seed, min_freq = 4)

  expect_true("decision making" %in% tolower(cand$term_en))
})

test_that("a heading's stripped point number never fabricates a bigram", {
  # Real-corpus bug: "## Point 10. Eliminate exhortations ..." lost its "10."
  # during tokenisation, leaving "Point" and "Eliminate" looking like a
  # genuine adjacent bigram that never existed in the source text.
  seed <- .mk_seed(character(0), character(0))
  segments <- .mk_segments(c(
    rep("Point 10. Eliminate exhortations for the workforce.", 4),
    rep("Point 11. Eliminate arbitrary numerical targets today.", 4)
  ))

  cand <- discover_candidates(segments, seed, min_freq = 4)

  expect_false("point eliminate" %in% tolower(cand$term_en))
  # The fix must not be a blunt hammer: a genuinely adjacent bigram either
  # side of the stripped gap is still discovered.
  expect_true("eliminate exhortations" %in% tolower(cand$term_en))
})

test_that("a table row's stripped cell numbers never fabricate a repeated-word bigram", {
  # Real-corpus bug: "| Worker 1 | Worker 2 | Worker 3 |" lost its digits and
  # pipes, leaving four adjacent "Worker" tokens that read as a recurring
  # "Worker Worker" bigram.
  seed <- .mk_seed(character(0), character(0))
  segments <- .mk_segments(rep("| Worker 1 | Worker 2 | Worker 3 | Worker 4 |", 6))

  cand <- discover_candidates(segments, seed, min_freq = 4)

  expect_false("worker worker" %in% tolower(cand$term_en))
})

test_that(".cap_phrases breaks a capitalised run at a bridging NA instead of spanning it", {
  # Without the NA, this is a single 5-token capitalised run (>= 4, so
  # normally captured whole). The NA must split it into two runs of 2 and 3
  # tokens, both below the length-4 cutoff, so neither survives.
  toks <- c("Deming", "Point", NA, "Eliminate", "Fear", "Now")

  expect_identical(.cap_phrases(toks), character(0))
})

test_that("known false-adjacency artifacts no longer appear when mining the real corpus", {
  segments <- glossary_segments(repo_root)
  seed <- read.csv(file.path(repo_root, "glossary", "seed-terms.csv"), stringsAsFactors = FALSE)

  cand <- discover_candidates(segments, seed, min_freq = 5)

  artifacts <- c("point eliminate", "point institute", "disease short", "step step", "worker worker")
  expect_equal(sum(tolower(cand$term_en) %in% artifacts), 0L)
})

# ---------------------------------------------------------------------------
# 6. Determinism and edge cases.
# ---------------------------------------------------------------------------

test_that("discover_candidates is deterministic", {
  seed <- .mk_seed(character(0), character(0))
  segments <- .mk_segments(rep("The Widget Assembly Protocol was reviewed again.", 5))

  a <- discover_candidates(segments, seed, min_freq = 3)
  b <- discover_candidates(segments, seed, min_freq = 3)

  expect_identical(a, b)
})

test_that("empty segments yield an empty, correctly-shaped result", {
  seed <- .mk_seed(character(0), character(0))
  segments <- .mk_segments(character(0))

  cand <- discover_candidates(segments, seed, min_freq = 1)

  expect_equal(nrow(cand), 0L)
  expect_identical(
    colnames(cand),
    c("term_en", "fr_rendering", "source", "frequency", "occurrence_types", "contexts", "decision_needed")
  )
})

test_that("results are sorted by frequency desc, then term_en asc", {
  seed <- .mk_seed(character(0), character(0))
  segments <- .mk_segments(c(
    rep("Please inspect the control chart today.", 6),
    rep("The Widget Assembly Protocol was reviewed again.", 4)
  ))

  cand <- discover_candidates(segments, seed, min_freq = 3)

  expect_true(all(diff(cand$frequency) <= 0))
})

# ---------------------------------------------------------------------------
# 7. Real-corpus integration smoke test (mirrors test-glossary-corpus.R).
# ---------------------------------------------------------------------------

test_that("discover_candidates on the real corpus never reproduces a seeded term/alias", {
  segments <- glossary_segments(repo_root)
  seed <- read.csv(file.path(repo_root, "glossary", "seed-terms.csv"), stringsAsFactors = FALSE)

  cand <- discover_candidates(segments, seed, min_freq = 10)

  excluded <- .seed_exclusion_set(seed)
  expect_equal(sum(.norm_term(cand$term_en) %in% excluded), 0L)
  expect_true(all(cand$decision_needed))
  expect_true(all(is.na(cand$fr_rendering)))
})
