# --- old-origin bridge tree (issue #888, Stage 1) ---
#
# Acceptance criteria under test:
#   * Every .html page under the site root gets a bridge page at the same
#     path, and nothing else from the site is copied (assets fall to the 301).
#   * Each page's placeholders become that page's own new-origin URL: the
#     canonical link, the <noscript> refresh and both continue links.
#   * The real template has exactly the placeholders the generator fills, and
#     none survive into the output.
#   * The .htaccess 301s to the new origin, path kept, with / exempt.
#   * The output directory is emptied first, so a removed page doesn't linger.

source(here::here("R/functions/old-origin-bridge.R"))

.template <- here::here("deploy/old-origin-bridge.html")

.read <- function(path) {
  x <- readChar(path, file.info(path)$size, useBytes = TRUE)
  Encoding(x) <- "UTF-8"
  x
}

.mk_site <- function() {
  root <- file.path(tempfile("site"), "_book")
  for (f in c("index.html", "privacy.html", "content/days/day-01/01-overture.html",
              "site_libs/quarto.js", "sitemap.xml", "robots.txt")) {
    dir.create(dirname(file.path(root, f)), recursive = TRUE, showWarnings = FALSE)
    writeLines("x", file.path(root, f))
  }
  root
}

test_that("each page gets a bridge copy at the same path, and nothing else is copied", {
  root <- .mk_site()
  out <- file.path(dirname(root), "_bridge")
  n <- build_old_origin_bridge(root, out, .template, "https://learndeming.org/")

  expect_equal(n, 3)
  expect_setequal(
    list.files(out, recursive = TRUE, all.files = TRUE),
    c(".htaccess", "index.html", "privacy.html", "content/days/day-01/01-overture.html")
  )
})

test_that("every placeholder becomes the page's own new-origin URL", {
  root <- .mk_site()
  out <- file.path(dirname(root), "_bridge")
  build_old_origin_bridge(root, out, .template, "https://learndeming.org")

  page <- .read(file.path(out, "content/days/day-01/01-overture.html"))
  url <- "https://learndeming.org/content/days/day-01/01-overture.html"
  expect_no_match(page, "__NEW_URL__", fixed = TRUE)
  expect_match(page, sprintf('<link rel="canonical" href="%s">', url), fixed = TRUE)
  expect_match(page, sprintf('<meta http-equiv="refresh" content="0; url=%s">', url), fixed = TRUE)
  expect_match(page, sprintf('<a id="continue" href="%s">', url), fixed = TRUE)
  expect_match(page, sprintf('<a id="continue-large" href="%s">', url), fixed = TRUE)
  expect_match(.read(file.path(out, "index.html")),
               '<link rel="canonical" href="https://learndeming.org/index.html">', fixed = TRUE)
})

test_that("the template's placeholders are exactly the four the pages need", {
  tpl <- .read(.template)
  expect_equal(lengths(regmatches(tpl, gregexpr("__NEW_URL__", tpl, fixed = TRUE))), 4)
  expect_error(render_bridge_page("<p>no placeholder</p>", "u"), "placeholder")
})

test_that("URLs are escaped for an HTML attribute", {
  expect_equal(render_bridge_page('<a href="__NEW_URL__">', 'https://x.org/a"b&c.html'),
               '<a href="https://x.org/a&quot;b&amp;c.html">')
})

test_that(".htaccess 301s every path without a file to the same path on the new origin", {
  root <- .mk_site()
  out <- file.path(dirname(root), "_bridge")
  build_old_origin_bridge(root, out, .template, "https://learndeming.org/")

  ht <- .read(file.path(out, ".htaccess"))
  expect_match(ht, "DirectoryIndex index.html", fixed = TRUE)
  expect_match(ht, "RewriteCond %{REQUEST_FILENAME} !-f", fixed = TRUE)
  expect_match(ht, "RewriteCond %{REQUEST_FILENAME}/index.html !-f", fixed = TRUE)
  expect_match(ht, "RewriteRule ^ https://learndeming.org%{REQUEST_URI} [R=301,L,NE]", fixed = TRUE)
  expect_no_match(ht, "NEW_ORIGIN", fixed = TRUE)
})

test_that("the output directory is emptied first", {
  root <- .mk_site()
  out <- file.path(dirname(root), "_bridge")
  dir.create(out)
  writeLines("stale", file.path(out, "removed-page.html"))
  build_old_origin_bridge(root, out, .template, "https://learndeming.org")
  expect_false(file.exists(file.path(out, "removed-page.html")))
})
