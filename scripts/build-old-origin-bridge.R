#!/usr/bin/env Rscript
#
# build-old-origin-bridge.R — writes _bridge/, what the rsync `deploy` job
# ships to deming.leedurbin.co.nz during #888's Stage 1: one bridge page per
# page of the site, plus an .htaccess that 301s everything else. See
# R/functions/old-origin-bridge.R; this file is only the plumbing.
#
# Run after `quarto render`, from the project root.

source(here::here("R/functions/old-origin-bridge.R"))

site_url <- yaml::read_yaml(here::here("_quarto.yml"))$book$`site-url`
if (is.null(site_url)) stop("_quarto.yml: book$site-url is not set")

count <- build_old_origin_bridge(
  site_root = here::here("_book"),
  out_dir = here::here("_bridge"),
  template_path = here::here("deploy/old-origin-bridge.html"),
  new_origin = site_url
)
cat(sprintf("build-old-origin-bridge.R: wrote %d bridge page(s) and .htaccess to _bridge/\n", count))
