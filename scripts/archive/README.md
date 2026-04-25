# Archived Scripts

These scripts were part of earlier conversion approaches during the project's evolution. They were superseded by the per-day workflow archived at `workflow/archive/CONVERSION_PROCESS.md`. For ongoing patterns and conventions, see `workflow/PATTERNS.md`.

## What's here

- **Python extraction tools** (`extract-content.py`, `extract-content-simple.py`, `smart-extract.py`, `streamlined-converter.py`, `structure-content.py`) — early attempts at automated PDF-to-Quarto conversion
- **Analysis/mapping tools** (`analyze-day-content.sh`, `identify-figures.py`, `map-interactive-elements.py`, `quality-control.py`) — content analysis utilities from the bulk-conversion approach
- **Quarto config tools** (`update-quarto-config.py`, `update-quarto-example.sh`, `new_day_from_file.sh`) — scaffolding generators
- **Deployment** (`upload.sh`) — manual scp deploy, replaced by GitHub Actions CI/CD
- **Support files** (`requirements.txt`, `day-2-chapters.txt`) — dependencies and data for archived tools
- **Documentation** (`README_analysis_tools.md`, `README_figure_extraction.md`, `README_interactive_elements.md`) — docs for the above tools

## Current workflow

Active scripts remain in `scripts/`:
- `pdf_to_png_converter.R` — converts PDF pages to PNGs for reconnaissance
- `convert_pdf.sh` — shell wrapper for the R converter
- `README_pdf_converter.md` — documentation for the converter
