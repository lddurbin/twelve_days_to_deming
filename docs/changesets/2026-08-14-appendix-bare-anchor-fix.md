## 2026-08-14 — Fix fragile same-file "page N" links in the Optional Extras appendix

- **Section**: Fixed
- **What**: Four "page N" links in the Optional Extras appendix used a bare `#sec-pageN` fragment instead of an explicit file path; one of them (`#sec-page43`) collided with an identical anchor id on a Day 2 page. All four now link explicitly to their own file.
- **PR**: #644
