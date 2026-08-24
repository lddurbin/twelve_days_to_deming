## 2026-08-25 — Enforce Subresource Integrity on the Observable Plot import

- **Section**: Infrastructure & Quality
- **What**: The pinned `@observablehq/plot@0.6.16` dynamic import behind Day 3's funnel-experiment histograms now enforces Subresource Integrity via an import map, so a compromised or altered CDN response fails closed instead of executing silently.
- **PR**: TBD
