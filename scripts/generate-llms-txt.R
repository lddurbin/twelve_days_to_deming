#!/usr/bin/env Rscript
#
# generate-llms-txt.R — project pre-render step (see #511)
#
# Writes llms.txt to the project root from _quarto-en.yml's chapter list and
# each chapter's own front matter, before Quarto's `resources:` copy step
# runs. See R/functions/llms-txt.R for the generation logic and why this
# runs as a pre-render step rather than a filter or knitr chunk.

source(here::here("R/functions/llms-txt.R"))

path <- llms_txt_write(here::here("llms.txt"), here::here("_quarto.yml"), here::here("_quarto-en.yml"))
cat(sprintf("generate-llms-txt.R: wrote %s\n", path))
