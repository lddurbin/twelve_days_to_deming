## 2026-08-14 — Fix broken and misrouted "page N" links on Day 1

- **Section**: Fixed
- **What**: Ten same-day "page N" links in Day 1 used a bare `#sec-pageN` fragment instead of an explicit file path; two silently misrouted readers to Day 2 or Day 3, and one pointed at a page anchor that doesn't exist. All ten now link to their correct target with an explicit path.
- **PR**: #642
