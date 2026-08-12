## 2026-08-13 — Fix Day 3 lookup table spilling past the page edge on mobile

- **Section**: Visual & Content Polish
- **What**: The Rule 3 marble-position lookup table in Day 3's Funnel Experiment (and the Rules 1–4 summary statistics table) now scrolls horizontally within its own container on narrow screens instead of forcing the whole page to overflow.
- **PR**: #609
