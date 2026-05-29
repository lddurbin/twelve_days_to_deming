# --- r-string extract / intra-line reinject / round-trip (issue #324) ---
#
# Extends the #323 prose extractor to pull USER-FACING string literals out of R
# code as a distinct `r-string` segment kind, via sub-line (character-offset)
# addressing. The hard gates:
#   * a whitelisted label literal IS extracted as `r-string`;
#   * a non-user-facing literal (file path / data key / colour / factor level)
#     is NOT extracted;
#   * intra-line reinjection of a TRANSLATION rewrites only the literal and
#     leaves the rest of the line byte-identical;
#   * the identity round-trip stays byte-identical with r-strings included,
#     across BOTH the .qmd corpus and the new .R helper corpus.
#
# Kept in a SEPARATE file from test-prose-extract.R so issue #325 (OJS/JS) can
# extend the same machinery without churning the #323 suite.

source(here::here("R/translation/prose-extract.R"))

repo_root <- here::here()

# Small helper: collect the r-string segments from an extraction.
.r_strings <- function(ex) {
  Filter(function(s) identical(as.character(s$address$kind), "r-string"), ex$segments)
}

# ---------------------------------------------------------------------------
# 1. A whitelisted label literal IS extracted as `r-string`.
# ---------------------------------------------------------------------------

test_that("ggtitle() / labs() / annotate('text') label literals are extracted as r-string", {
  tmp <- tempfile(fileext = ".qmd")
  writeLines(c(
    "---", 'title: "T"', "---", "",
    "Some prose.", "",
    "```{r}",
    'p <- ggplot() + ggtitle("A1") +',
    '  labs(x = "Shaft diameter", y = "Density") +',
    '  annotate("text", x = 0, y = 0, label = "PSYCHOLOGY")',
    "```", "",
    "Prose after."
  ), tmp)
  ex <- extract_qmd(tmp)
  rs <- .r_strings(ex)
  texts <- vapply(rs, function(s) as.character(s$text), character(1))
  expect_true("A1" %in% texts)
  expect_true("Shaft diameter" %in% texts)
  expect_true("Density" %in% texts)
  expect_true("PSYCHOLOGY" %in% texts)
  # Every r-string carries character-offset sub-line addressing.
  for (s in rs) {
    expect_identical(as.character(s$address$kind), "r-string")
    expect_true(as.integer(s$address$start_col) >= 1L)
    expect_true(as.integer(s$address$end_col) >= as.integer(s$address$start_col) - 1L)
    expect_identical(as.integer(s$address$start_line), as.integer(s$address$end_line))
  }
})

test_that("helper DEFAULT-argument labels in a multi-line function() signature are extracted", {
  tmp <- tempfile(fileext = ".R")
  writeLines(c(
    "ford_histogram_plot <- function(values,",
    "                                lsl_at,",
    '                                lsl_label = "Lower\\nSpecification\\nLimit",',
    '                                x_title   = "Shaft diameter",',
    "                                fill_colour = CHART_LINE_COLOUR) {",
    "  ggplot()",
    "}"
  ), tmp)
  ex <- extract_r_file(tmp)
  texts <- vapply(.r_strings(ex), function(s) as.character(s$text), character(1))
  expect_true("Lower\\nSpecification\\nLimit" %in% texts)  # raw bytes incl literal \n
  expect_true("Shaft diameter" %in% texts)
  # fill_colour's default is a VARIABLE, not a literal -> nothing to extract.
  expect_false(any(grepl("CHART_LINE_COLOUR", texts)))
})

test_that("R escapes inside an r-string are masked off the translator surface", {
  tmp <- tempfile(fileext = ".R")
  writeLines(c(
    "f <- function(lsl_label = \"Lower\\nLimit\") { ggplot() }"
  ), tmp)
  ex <- extract_r_file(tmp)
  rs <- .r_strings(ex)
  expect_length(rs, 1L)
  s <- rs[[1]]
  # the masked surface must not expose the raw backslash-n escape
  expect_false(grepl("\\\\n", as.character(s$masked)))
  expect_true(any(vapply(s$placeholders, function(p) p$kind == "r_escape", logical(1))))
})

# ---------------------------------------------------------------------------
# 2. Non-user-facing literals are NOT extracted (logic must never be touched).
# ---------------------------------------------------------------------------

test_that("file paths, data keys, factor levels and hex colours are NOT extracted", {
  excluded_lines <- c(
    'source(here::here("R/data/day-03-six-processes.R"))',
    'geom_histogram(fill = "magenta", colour = "#000000")',
    'scale_colour_manual(values = c("#ff0000", "blue"))',
    'df |> gt(rowname_col = "Name")',
    'factor(x, levels = c("in", "out"))',
    'annotate("segment", x = 0, label = "should-not-extract")',
    'tab_options(table.background.color = "white")',
    'theme(legend.position = "bottom")'
  )
  for (ln in excluded_lines) {
    kept <- .scan_code_line_literals(ln)
    expect_length(kept, 0L)
  }
})

test_that("non-R code chunks are not scanned for r-strings", {
  tmp <- tempfile(fileext = ".qmd")
  writeLines(c(
    "---", 'title: "T"', "---", "",
    "```{ojs}",
    'md`A label "looks like" a string`',
    "```", "",
    "```{python}",
    'plt.title("Not extracted")',
    "```"
  ), tmp)
  ex <- extract_qmd(tmp)
  expect_length(.r_strings(ex), 0L)
})

# ---------------------------------------------------------------------------
# 3. Intra-line reinjection rewrites only the literal; rest of line identical.
# ---------------------------------------------------------------------------

test_that("reinjecting a TRANSLATION rewrites only the literal, leaving the line byte-identical otherwise", {
  tmp <- tempfile(fileext = ".qmd")
  writeLines(c(
    "---", 'title: "T"', "---", "",
    "```{r}",
    'p <- ggplot() + ggtitle("A1") + labs(x = "Shaft diameter")',
    "```"
  ), tmp)
  ex <- extract_qmd(tmp)
  rs <- .r_strings(ex)
  target <- NULL
  for (s in rs) if (identical(as.character(s$text), "Shaft diameter")) target <- s$id
  expect_false(is.null(target))

  translation <- "Diametre de l'arbre"
  rebuilt <- reinject_qmd(tmp, ex, replacements = setNames(list(translation), target))
  # Select the code line by a stable token, not a fixed index, so the assertion
  # survives any change to the fixture's front matter line count.
  rebuilt_lines <- strsplit(rebuilt, "\n", fixed = TRUE)[[1]]
  rebuilt_line <- rebuilt_lines[grep("ggtitle", rebuilt_lines, fixed = TRUE)[[1]]]

  # the only change on the line is INSIDE the targeted literal's quotes
  expect_true(grepl('ggtitle("A1")', rebuilt_line, fixed = TRUE))   # untouched
  expect_true(grepl(translation, rebuilt_line, fixed = TRUE))       # translated
  expect_false(grepl("Shaft diameter", rebuilt_line, fixed = TRUE)) # replaced
  # prefix and suffix bytes around the literal are exactly preserved
  expect_true(startsWith(rebuilt_line, 'p <- ggplot() + ggtitle("A1") + labs(x = "'))
  expect_true(endsWith(rebuilt_line, paste0(translation, '")')))
})

test_that("reinjecting two literals on one line splices both correctly", {
  tmp <- tempfile(fileext = ".qmd")
  writeLines(c(
    "---", 'title: "T"', "---", "",
    "```{r}",
    'labs(x = "Shaft diameter", y = "Density")',
    "```"
  ), tmp)
  ex <- extract_qmd(tmp)
  rs <- .r_strings(ex)
  repl <- list()
  for (s in rs) {
    if (identical(as.character(s$text), "Shaft diameter")) repl[[s$id]] <- "Diametre"
    if (identical(as.character(s$text), "Density"))        repl[[s$id]] <- "Densite"
  }
  rebuilt <- reinject_qmd(tmp, ex, replacements = repl)
  rebuilt_lines <- strsplit(rebuilt, "\n", fixed = TRUE)[[1]]
  line <- rebuilt_lines[grep("labs(", rebuilt_lines, fixed = TRUE)[[1]]]
  expect_identical(line, 'labs(x = "Diametre", y = "Densite")')
})

# ---------------------------------------------------------------------------
# 4. Identity round-trip stays byte-identical WITH r-strings included.
# ---------------------------------------------------------------------------

test_that("identity round-trip is byte-identical for the .R helper corpus", {
  files <- r_corpus(repo_root)
  expect_gt(length(files), 0)
  failures <- character(0)
  for (f in files) {
    rel <- sub(paste0("^", normalizePath(repo_root), "/?"), "", normalizePath(f))
    r <- roundtrip_file(f, rel_path = rel)
    if (!isTRUE(r$ok)) failures <- c(failures, sprintf("%s (byte %s)", rel, r$first_diff_byte))
  }
  expect_identical(failures, character(0),
                   info = paste("non-identical .R files:", paste(failures, collapse = "; ")))
})

test_that("identity round-trip is byte-identical for .qmd files that contain r-strings", {
  # day-03 chart file carries ggtitle("A1")/("A2") in an R chunk.
  f <- file.path(repo_root, "content", "days", "day-03",
                 "05-how-do-we-compute-control-limits.qmd")
  skip_if_not(file.exists(f))
  ex <- extract_qmd(f)
  expect_gt(length(.r_strings(ex)), 0)            # r-strings really are present
  expect_true(roundtrip_file(f)$ok)               # and round-trip survives them
})

test_that("a synthetic file with escapes, format specifiers and quotes round-trips byte-identical", {
  tmp <- tempfile(fileext = ".R")
  writeLines(c(
    "f <- function(",
    '  lsl_label = "Lower\\nSpecification\\nLimit",',
    '  caption = "12 subgroups of size 4") {',
    '  annotate("text", label = "USL") +',
    '    ggtitle("A1")',
    "}"
  ), tmp)
  expect_true(roundtrip_file(tmp)$ok)
  # and the expected labels were seen, including the caption default
  texts <- vapply(.r_strings(extract_r_file(tmp)), function(s) as.character(s$text), character(1))
  expect_true("USL" %in% texts)
  expect_true("A1" %in% texts)
  expect_true("12 subgroups of size 4" %in% texts)
})
