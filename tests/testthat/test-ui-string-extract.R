# --- UI / ARIA string extraction (issue #325) ---
#
# Extends the #323 prose + #324 r-string machinery to pull USER-FACING interface
# strings out of three NEW surfaces, as TWO distinct segment kinds that carry
# interface context:
#   * `ui-string`  — visible UI text (OJS Inputs.* label/placeholder, JS button
#                    textContent / input placeholder).
#   * `aria-label` — assistive-technology text (raw-HTML aria-label attribute
#                    values, JS setAttribute("aria-label", …), live-region
#                    announcements).
#
# Hard gates exercised here:
#   * OJS Inputs.textarea label+placeholder are extracted as `ui-string`;
#   * a setAttribute("aria-label", …) value and a `.textContent =` value extract
#     with the correct kinds;
#   * a backtick template literal masks its `${…}` interpolation off the
#     translator surface and round-trips byte-identical;
#   * a non-user-facing JS literal (id template / class name / SVG markup / role
#     token / selector) is NOT extracted;
#   * a raw-HTML aria-label value is extracted while role=/class= are NOT;
#   * the identity round-trip stays byte-identical with all new kinds included,
#     across the .qmd, .R and the new .js corpus.
#
# Kept in a SEPARATE file from test-prose-extract.R / test-r-string-extract.R so
# the #323/#324 suites are not churned (per the issue's hard constraint).

source(here::here("R/translation/prose-extract.R"))

repo_root <- here::here()

# Collect segments of a given kind from an extraction.
.of_kind <- function(ex, kind) {
  Filter(function(s) identical(as.character(s$address$kind), kind), ex$segments)
}
.texts <- function(segs) vapply(segs, function(s) as.character(s$text), character(1))

# ---------------------------------------------------------------------------
# (a) OJS Inputs.textarea label + placeholder are extracted as `ui-string`.
# ---------------------------------------------------------------------------

test_that("OJS Inputs.textarea label and placeholder are extracted as ui-string", {
  tmp <- tempfile(fileext = ".qmd")
  writeLines(c(
    "---", 'title: "T"', "---", "",
    "Some prose.", "",
    "```{ojs}",
    'viewof thought_9a = Inputs.textarea({label: "What is the difference?", placeholder: "Type here.", rows: 10})',
    "```", "",
    "```{ojs download_all}",
    'createDownloadButton([viewof thought_9a], "day9_notes.txt")',
    "```"
  ), tmp)
  ex <- extract_qmd(tmp)
  ui <- .of_kind(ex, "ui-string")
  texts <- .texts(ui)
  expect_true("What is the difference?" %in% texts)
  expect_true("Type here." %in% texts)
  # The createDownloadButton filename is NOT a label — must stay untouched.
  expect_false("day9_notes.txt" %in% texts)
  # `rows: 10` is numeric, not a string literal — nothing to extract there.
  for (s in ui) {
    expect_identical(as.character(s$address$kind), "ui-string")
    expect_identical(as.character(s$address$context), "ojs-input")
    expect_identical(as.integer(s$address$start_line), as.integer(s$address$end_line))
  }
})

# ---------------------------------------------------------------------------
# (b) setAttribute("aria-label", …) and .textContent = extract w/ correct kinds.
# ---------------------------------------------------------------------------

test_that("JS setAttribute(aria-label) and textContent assignment extract with correct kinds", {
  tmp <- tempfile(fileext = ".js")
  writeLines(c(
    'export function build() {',
    '  const button = document.createElement("button");',
    '  button.textContent = "Download Your Notes";',
    '  button.setAttribute("aria-label", "Save your work");',
    '  button.setAttribute("role", "button");',
    '  button.setAttribute("tabindex", "0");',
    '  return button;',
    '}'
  ), tmp)
  ex <- extract_js_file(tmp)
  ui <- .texts(.of_kind(ex, "ui-string"))
  aria <- .texts(.of_kind(ex, "aria-label"))
  expect_true("Download Your Notes" %in% ui)     # textContent -> ui-string
  expect_true("Save your work" %in% aria)         # aria-label value -> aria-label
  # setAttribute("role"/"tabindex", …) values are NOT user-facing.
  expect_false("button" %in% c(ui, aria))
  expect_false("0" %in% c(ui, aria))
  # The attribute/element name args ("aria-label","role","tabindex") and the
  # createElement tag ("button") are never extracted.
  expect_false("aria-label" %in% c(ui, aria))
})

test_that("JS placeholder assignment extracts as ui-string", {
  tmp <- tempfile(fileext = ".js")
  writeLines(c('input.placeholder = "Your name";'), tmp)
  ex <- extract_js_file(tmp)
  expect_identical(.texts(.of_kind(ex, "ui-string")), "Your name")
})

# ---------------------------------------------------------------------------
# (c) A backtick template literal masks its ${…} interpolation and round-trips.
# ---------------------------------------------------------------------------

test_that("backtick template literal masks ${...} interpolation off the translator surface", {
  tmp <- tempfile(fileext = ".js")
  writeLines(c(
    'function status(rule, counter, total) {',
    '  announceFunnelStatus(`Rule ${rule}, stage ${counter} of ${total}.`);',
    '}'
  ), tmp)
  ex <- extract_js_file(tmp)
  aria <- .of_kind(ex, "aria-label")
  expect_length(aria, 1L)
  s <- aria[[1]]
  # raw text keeps the exact interpolation bytes ...
  expect_true(grepl("${rule}", as.character(s$text), fixed = TRUE))
  # ... but the masked surface a translator sees must NOT expose any ${...}.
  expect_false(grepl("$\\{", as.character(s$masked)))
  expect_false(grepl("${", as.character(s$masked), fixed = TRUE))
  # three interpolations were masked as js_interp placeholders
  n_interp <- sum(vapply(s$placeholders, function(p) p$kind == "js_interp", logical(1)))
  expect_identical(n_interp, 3L)
})

test_that("multi-line announceFunnelStatus message on a continuation line is extracted", {
  tmp <- tempfile(fileext = ".js")
  writeLines(c(
    "if (counter > 0) {",
    "  announceFunnelStatus(",
    "    `Rule ${rule}, stage ${counter}.`",
    "  );",
    "}"
  ), tmp)
  ex <- extract_js_file(tmp)
  aria <- .texts(.of_kind(ex, "aria-label"))
  expect_true("Rule ${rule}, stage ${counter}." %in% aria)
})

test_that("a backtick UI literal with ${...} round-trips byte-identical and translates cleanly", {
  tmp <- tempfile(fileext = ".js")
  writeLines(c(
    'label.textContent = `Area ${String.fromCharCode(65 + i)}:`;'
  ), tmp)
  # identity round-trip is byte-identical
  expect_true(roundtrip_file(tmp)$ok)
  ex <- extract_js_file(tmp)
  ui <- .of_kind(ex, "ui-string")
  expect_length(ui, 1L)
  s <- ui[[1]]
  # Translating the masked form (with the interpolation token preserved) splices
  # only the literal's inner span; ${...} survives intact and logic is unchanged.
  translated <- sub("Area", "Zone", as.character(s$masked))            # "Zone PH1:"
  translated <- .unmask_inline(translated, s$placeholders)             # "Zone ${...}:"
  rebuilt <- reinject_qmd(tmp, ex, replacements = setNames(list(translated), s$id))
  expect_true(grepl("label.textContent = `Zone ${String.fromCharCode(65 + i)}:`;",
                    rebuilt, fixed = TRUE))
})

# ---------------------------------------------------------------------------
# (d) Non-user-facing JS literals are NOT extracted (logic must never break).
# ---------------------------------------------------------------------------

test_that("id templates, class names, SVG markup, role tokens and selectors are NOT extracted", {
  excluded_lines <- c(
    'const id = `track-title-${id}`;',                 # id template (not a label)
    'el.className = "fe-sr-live visually-hidden";',     # className is not whitelisted
    'svg += `<svg role="img" viewBox="0 0 10 10">`;',   # SVG structural markup
    'el.setAttribute("role", "status");',               # ARIA role token
    'el.setAttribute("aria-live", "polite");',          # ARIA live token
    'el.setAttribute("aria-atomic", "true");',          # ARIA atomic token
    'document.querySelector(".fe-status");',            # CSS selector
    'el.addEventListener("click", handler);',           # event name
    'cell.textContent = formatNet(net);',               # RHS is a call, not literal
    'cell.setAttribute("aria-label", buildCellLabel(cell));', # value is a call
    'if (rating === "empty") { return; }',              # equality test, not assignment
    'cell.textContent = "";'                            # empty string -> nothing
  )
  for (ln in excluded_lines) {
    kept <- .scan_ojs_js_line_literals(ln)
    expect_length(kept, 0L)
  }
})

test_that("an OJS object key that is not label/placeholder, or not inside Inputs.*, is NOT extracted", {
  # `rows:`/`value:` are not label props; a `label:` outside an Inputs.* call is
  # also excluded (we require the enclosing constructor to be whitelisted).
  expect_length(.scan_ojs_js_line_literals('Inputs.textarea({rows: "tall"})'), 0L)
  expect_length(.scan_ojs_js_line_literals('myWidget({label: "Not an Input"})'), 0L)
})

# ---------------------------------------------------------------------------
# (e) Raw-HTML aria-label value extracted while role= / class= are NOT.
# ---------------------------------------------------------------------------

test_that("raw-HTML aria-label value is extracted as aria-label while role=/class=/id= are not", {
  tmp <- tempfile(fileext = ".qmd")
  writeLines(c(
    "---", 'title: "T"', "---", "",
    '<div class="thought_commentary" role="note" aria-label="Commentary" id="c1">',
    "Prose inside.", "",
    "</div>"
  ), tmp)
  ex <- extract_qmd(tmp)
  aria <- .of_kind(ex, "aria-label")
  texts <- .texts(aria)
  expect_true("Commentary" %in% texts)            # aria-label value extracted
  expect_false("note" %in% texts)                 # role value NOT extracted
  expect_false("thought_commentary" %in% texts)   # class value NOT extracted
  expect_false("c1" %in% texts)                   # id value NOT extracted
  for (s in aria) {
    expect_identical(as.character(s$address$kind), "aria-label")
    expect_identical(as.character(s$address$context), "html-attr")
  }
})

test_that("raw-HTML alt/title/placeholder values are extracted as ui-string; aria-controls/data-* are not", {
  tmp <- tempfile(fileext = ".qmd")
  writeLines(c(
    "---", 'title: "T"', "---", "",
    '<div title="Open panel" aria-controls="panel-1" data-bs-target="#x">',
    "x",
    "</div>"
  ), tmp)
  ex <- extract_qmd(tmp)
  ui <- .texts(.of_kind(ex, "ui-string"))
  expect_true("Open panel" %in% ui)               # title -> ui-string
  expect_false("panel-1" %in% ui)                 # aria-controls NOT extracted
  expect_false("#x" %in% ui)                       # data-* NOT extracted
})

test_that("a whitelisted attribute name as the TAIL of a data-* attribute is NOT extracted", {
  # Regression guard: a `\b` boundary matches between the `-` and the name in
  # `data-aria-label`/`data-title`, so it would wrongly extract those values. The
  # negative-lookbehind guard must reject them while still taking the real
  # aria-label/title on the same tag.
  tmp <- tempfile(fileext = ".qmd")
  writeLines(c(
    "---", 'title: "T"', "---", "",
    paste0('<div data-aria-label="bad-aria" data-title="bad-title" ',
           'aria-label="Good aria" title="Good title">'),
    "x",
    "</div>"
  ), tmp)
  ex <- extract_qmd(tmp)
  aria <- .texts(.of_kind(ex, "aria-label"))
  ui   <- .texts(.of_kind(ex, "ui-string"))
  expect_true("Good aria" %in% aria)              # real aria-label extracted
  expect_true("Good title" %in% ui)               # real title extracted
  expect_false("bad-aria" %in% aria)              # data-aria-label NOT extracted
  expect_false("bad-aria" %in% ui)
  expect_false("bad-title" %in% c(aria, ui))      # data-title NOT extracted
})

# ---------------------------------------------------------------------------
# (f) Identity round-trip byte-identical with all new kinds included.
# ---------------------------------------------------------------------------

test_that("identity round-trip is byte-identical for the .js asset corpus", {
  files <- js_corpus(repo_root)
  expect_gt(length(files), 0)
  failures <- character(0)
  for (f in files) {
    rel <- sub(paste0("^", normalizePath(repo_root), "/?"), "", normalizePath(f))
    r <- roundtrip_file(f, rel_path = rel)
    if (!isTRUE(r$ok)) failures <- c(failures, sprintf("%s (byte %s)", rel, r$first_diff_byte))
  }
  expect_identical(failures, character(0),
                   info = paste("non-identical .js files:", paste(failures, collapse = "; ")))
})

test_that("the .js corpus really yields UI/ARIA segments (extraction is not vacuous)", {
  total <- 0L
  for (f in js_corpus(repo_root)) total <- total + length(extract_js_file(f)$segments)
  expect_gt(total, 0L)
})

test_that("identity round-trip is byte-identical for .qmd files that carry OJS/aria-label segments", {
  # day-09 carries OJS Inputs.textarea chunks and raw-HTML aria-label divs.
  f <- file.path(repo_root, "content", "days", "day-09", "02-a-system.qmd")
  skip_if_not(file.exists(f))
  ex <- extract_qmd(f)
  expect_gt(length(.of_kind(ex, "ui-string")), 0)   # OJS labels present
  expect_true(roundtrip_file(f)$ok)                  # and round-trip survives them
})

test_that("a synthetic .qmd mixing OJS, raw-HTML aria-label, prose and an R chunk round-trips", {
  tmp <- tempfile(fileext = ".qmd")
  writeLines(c(
    "---", 'title: "T"', "---", "",
    "Intro prose.", "",
    '<div class="thought" role="note" aria-label="Thought">',
    "Inner prose.",
    "</div>", "",
    "```{ojs}",
    'viewof a = Inputs.text({label: "Name", placeholder: "Type"})',
    "```", "",
    "```{r}",
    'ggplot() + ggtitle("Chart")',
    "```"
  ), tmp)
  expect_true(roundtrip_file(tmp)$ok)
  ex <- extract_qmd(tmp)
  expect_true("Thought" %in% .texts(.of_kind(ex, "aria-label")))
  expect_true(all(c("Name", "Type") %in% .texts(.of_kind(ex, "ui-string"))))
  expect_true("Chart" %in% .texts(.of_kind(ex, "r-string")))
})
