# --- self-referencing canonical links (issue #896) ---
#
# Acceptance criteria under test:
#   * A page gets exactly one canonical link to site-url plus its path under
#     _book/, inserted before </head>, with the rest of the file unchanged.
#   * index.html keeps its filename (/index.html, as the sitemap lists it),
#     and a page under _book/fr/ gets its /fr/ URL.
#   * 404.html, noindex pages, meta-refresh stubs and pages that already have
#     a canonical link are left untouched, so the step is idempotent.
#   * add_canonical_links() ignores non-.html files and files outside _book/.
#   * check_canonical_links() passes a correct site and names each failure.

source(here::here("R/functions/canonical-links.R"))

.site_url <- "https://learndeming.org"

.read_raw <- function(path) {
  readChar(path, file.info(path)$size, useBytes = TRUE)
}

#' Write `body` with no trailing newline, as Quarto does.
.write_raw <- function(path, body) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  con <- file(path, "wb")
  writeChar(body, con, eos = NULL, useBytes = TRUE)
  close(con)
  path
}

.page <- function(head_extra = "") {
  paste0(
    "<html><head>\n",
    '<meta name="description" content="Henry Neave’s course — free.">\n',
    head_extra,
    "</head><body><p>Body</p></body></html>"
  )
}

.mk_site <- function() {
  root <- file.path(tempfile("book"), "_book")
  dir.create(root, recursive = TRUE)
  root
}

test_that("canonical_url joins site-url and path with one slash", {
  expect_equal(canonical_url("index.html", "https://learndeming.org/"),
               "https://learndeming.org/index.html")
  expect_equal(canonical_url("content/a.html", "https://learndeming.org"),
               "https://learndeming.org/content/a.html")
})

test_that("add_canonical_link_in_file inserts one link before </head> and changes nothing else", {
  root <- .mk_site()
  path <- .write_raw(file.path(root, "page.html"), .page())
  url <- "https://learndeming.org/page.html"

  expect_true(add_canonical_link_in_file(path, url))

  expected <- sub("</head>", sprintf('<link rel="canonical" href="%s">\n</head>', url),
                  .page(), fixed = TRUE)
  expect_identical(charToRaw(.read_raw(path)), charToRaw(expected))
})

test_that("add_canonical_link_in_file is idempotent", {
  root <- .mk_site()
  path <- .write_raw(file.path(root, "page.html"), .page())
  url <- "https://learndeming.org/page.html"

  expect_true(add_canonical_link_in_file(path, url))
  once <- .read_raw(path)
  expect_false(add_canonical_link_in_file(path, url))
  expect_identical(.read_raw(path), once)
})

test_that("pages that shouldn't be canonical are left untouched", {
  root <- .mk_site()
  pages <- list(
    "404.html" = .page(),
    "noindex.html" = .page('<meta name="robots" content="noindex, follow">\n'),
    "stub.html" = .page('<meta http-equiv="refresh" content="0; url=index.fr.html">\n'),
    "no-head.html" = "<p>fragment</p>"
  )
  for (name in names(pages)) {
    path <- .write_raw(file.path(root, name), pages[[name]])
    expect_false(add_canonical_link_in_file(path, "https://learndeming.org/x.html"), label = name)
    expect_identical(charToRaw(.read_raw(path)), charToRaw(pages[[name]]), label = name)
  }
  expect_false(add_canonical_link_in_file(file.path(root, "missing.html"), "u"))
})

test_that("add_canonical_links derives URLs from the path under the site root", {
  root <- .mk_site()
  .write_raw(file.path(root, "index.html"), .page())
  .write_raw(file.path(root, "content/days/day-01/01-overture.html"), .page())
  .write_raw(file.path(root, "fr/content-fr/welcome.fr.html"), .page())
  .write_raw(file.path(root, "site_libs/app.js"), "x")
  outside <- .write_raw(file.path(dirname(root), "outside.html"), .page())

  files <- c(
    file.path(root, "index.html"),
    file.path(root, "content/days/day-01/01-overture.html"),
    file.path(root, "fr/content-fr/welcome.fr.html"),
    file.path(root, "site_libs/app.js"),
    outside,
    file.path(root, "gone.html")
  )
  expect_equal(add_canonical_links(files, .site_url, root), 3)

  expect_match(.read_raw(file.path(root, "index.html")),
               'href="https://learndeming.org/index.html"', fixed = TRUE)
  expect_match(.read_raw(file.path(root, "content/days/day-01/01-overture.html")),
               'href="https://learndeming.org/content/days/day-01/01-overture.html"', fixed = TRUE)
  expect_match(.read_raw(file.path(root, "fr/content-fr/welcome.fr.html")),
               'href="https://learndeming.org/fr/content-fr/welcome.fr.html"', fixed = TRUE)
  expect_no_match(.read_raw(outside), "canonical")
})

test_that("check_canonical_links passes a correct site and reports each failure", {
  root <- .mk_site()
  .write_raw(file.path(root, "sitemap.xml"), paste0(
    '<?xml version="1.0"?><urlset>',
    "<url><loc>https://learndeming.org/good.html</loc></url>",
    "</urlset>"
  ))
  .write_raw(file.path(root, "good.html"), .page())
  add_canonical_links(file.path(root, "good.html"), .site_url, root)
  expect_length(check_canonical_links(root, .site_url), 0)

  .write_raw(file.path(root, "sitemap.xml"), paste0(
    '<?xml version="1.0"?><urlset>',
    "<url><loc>https://learndeming.org/good.html</loc></url>",
    "<url><loc>https://learndeming.org/none.html</loc></url>",
    "<url><loc>https://learndeming.org/wrong.html</loc></url>",
    "<url><loc>https://learndeming.org/missing.html</loc></url>",
    "<url><loc>https://deming.leedurbin.co.nz/old.html</loc></url>",
    "</urlset>"
  ))
  .write_raw(file.path(root, "none.html"), .page())
  .write_raw(file.path(root, "wrong.html"),
             .page('<link rel="canonical" href="https://learndeming.org/other.html">\n'))

  problems <- check_canonical_links(root, .site_url)
  expect_length(problems, 4)
  expect_match(problems[1], "none.html: 0 canonical links")
  expect_match(problems[2], "wrong.html: canonical points at https://learndeming.org/other.html")
  expect_match(problems[3], "missing.html: .* is missing")
  expect_match(problems[4], "old.html: not under https://learndeming.org/")
})

test_that("check_canonical_links reports a missing sitemap", {
  expect_match(check_canonical_links(.mk_site(), .site_url), "sitemap.xml is missing")
})
