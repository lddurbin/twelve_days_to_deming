# Project-wide R setup for Quarto rendering
# Sourced automatically via .Rprofile — no per-chapter setup chunk needed.
# See: https://github.com/lddurbin/twelve_days_to_deming/issues/68

knitr::knit_hooks$set(crop = knitr::hook_pdfcrop)

# Touch the svglite namespace so renv's implicit-mode snapshot picks it
# up as a direct dependency. The `dev = "svglite"` knitr option below
# resolves the package by name string at chunk-evaluation time, which
# renv's static analysis does not see.
requireNamespace("svglite", quietly = TRUE)

# Emit chart figures as inline SVG (via svglite) instead of PNG so that
# Darkly-mode CSS in main.css can re-skin axis ink without re-rendering.
# `bg = "transparent"` suppresses svglite's default white canvas rect so
# the dark page colour shows through under dark mode.
# See R/functions/main-functions.R top-of-file conventions block for the
# colour-token contract and the dark-mode override mechanism.
knitr::opts_chunk$set(
  dev = "svglite",
  dev.args = list(bg = "transparent")
)

# Inline SVG into the rendered HTML rather than leaving it as
# `<img src="…svg">`. img-wrapped SVG renders in an isolated context that
# the parent document's CSS cannot reach — which would defeat the whole
# point of the dark-mode override mechanism. Inlining preserves Quarto's
# figure/lightbox treatment (the figure wrapper is built around our
# returned HTML, not around an img tag we replaced post-hoc).
#
# Scope:
#   - HTML output only (PDF / docx keep the default img path).
#   - SVG plots only (PNG plots, if any chunk ever opts out of svglite,
#     fall through to knitr's default hook).
# Note: dark-mode re-skin happens via CSS `filter: invert(1) hue-rotate(180deg)`
# applied to chart `<img src="…svg">` elements in assets/styles/main.css.
# That trick lets us keep the default `<img>`-wrapped embedding (which
# Quarto controls and which a knitr plot-hook would otherwise need to
# fight) while still flipping brightness for axis ink and gridlines, with
# the hue-rotate preserving chromatic colours (the red data line, the
# blue control limits) roughly intact through the round-trip.

source(file.path("R", "functions", "main-functions.R"))
