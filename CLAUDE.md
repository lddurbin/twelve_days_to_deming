# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

"12 Days to Deming" is an interactive educational course based on Dr. W. Edwards Deming's teachings, built as a Quarto book with R backend. The project converts traditional PDF-based course materials into an interactive web experience with embedded activities, timing indicators, and modern web features.

## Development Commands

### Core Commands
- **Build the book**: `quarto render`
- **Preview during development**: `quarto preview` 
- **Clean build artifacts**: `rm -rf _book/`

### R Environment
- **Restore R dependencies**: `Rscript -e 'renv::restore()'`
- **Check environment status**: `Rscript -e 'renv::status()'`
- **Install new packages**: Use renv workflow - `Rscript -e 'renv::install("package_name"); renv::snapshot()'`

### Deployment
- **Manual deploy**: Handled via GitHub Actions on push to main
- **Force rebuild**: Use GitHub Actions workflow dispatch

## Architecture Overview

### Core Structure
- **Quarto Configuration**: `_quarto.yml` defines the book structure, theme, and build settings
- **Content Organization**: `/content/days/` contains structured course material organized by day
- **R Environment**: Uses `renv` for reproducible package management with `renv.lock`
- **Assets**: `/assets/` contains CSS, JavaScript, images, and templates

### Content Architecture
- **Modular Design**: Each day is broken into multiple `.qmd` files for specific topics/activities
- **Progressive Structure**: 12 days of content, with days 1-2 fully interactive, remaining days in development
- **Active Learning**: Embedded activities, exercises, and interactive elements throughout

### Key Components
- **Interactive Elements**: Custom JavaScript in `/assets/scripts/functions.js` handles user interactions like note downloading
- **Styling**: Custom CSS in `/assets/styles/main.css` with Cosmo theme base
- **R Integration**: R scripts in `/R/` handle data analysis, visualizations, and statistical content
- **Build Scripts**: `/scripts/` contains the PDF-to-PNG converter; obsolete tools are in `/scripts/archive/`

### Data Flow
1. **Source**: `.qmd` files with embedded R code and interactive elements
2. **Processing**: Quarto renders through R/knitr with renv environment
3. **Output**: Static HTML site in `/_book/` directory
4. **Deploy**: GitHub Actions automates build and deployment to production server

## Development Workflow

### Local Development
1. Ensure R and Quarto are installed
2. Use `renv::restore()` to set up R environment
3. Use `quarto preview` for live development
4. Make changes to `.qmd` files in `/content/days/`
5. Build with `quarto render` before committing

### Content Structure Guidelines
- Follow existing naming patterns: `day-XX/##-topic-name.qmd`
- **Exact transcription required**: Provide word-for-word copy of original content from PDF sources
- Interactive elements should enhance, not replace, original pedagogical flow
- Use consistent timing indicators and activity formatting
- User will always verify transcription accuracy

### Key Dependencies
- **Quarto**: Document publishing system
- **R 4.4.0+**: Statistical computing environment  
- **renv**: R package dependency management
- **Core R packages**: DiagrammeR, ggplot2, dplyr, knitr, rmarkdown
- **System dependencies**: pandoc, various system libraries for R package compilation

## Image Extraction Workflow

### Cropping Figures from PDF Sources
When extracting tables, charts, photos, or other figures from original PDF materials in `12-Days-to-Deming/PNGs/`:

1. **Identify Source**: Find the correct PNG file (e.g., `E.Day.2.12Oct21_page_046.png`)
2. **Check Image Dimensions**: Use `magick identify filename.png` to understand scale
3. **Iterative Cropping Process**:
   - Start with approximate coordinates: `magick "source.png" -crop WIDTHxHEIGHT+X+Y "output.png"`
   - View result with `Read` tool
   - Adjust boundaries incrementally until perfect
4. **Target Directory**: Save cropped images to `assets/images/day-XX/`
5. **Naming Convention**: Use descriptive names (e.g., `postscript-table.png`, `control-chart-example.png`)

**Key Tips**:
- PDF conversions are high-resolution (typically 2550x3300+), so coordinates need scaling
- Extend boundaries slightly in all directions to capture complete elements
- Include all relevant headers, labels, and annotations
- Stop cropping just before unwanted text or elements
- Test multiple coordinate adjustments to get precise boundaries

### Usage in Quarto
Reference cropped images in `.qmd` files:
```markdown
![Description](/assets/images/day-XX/filename.png){.lightbox}
```

## Deployment Architecture

- **GitHub Actions**: `.github/workflows/deploy.yml` handles automated builds
- **Production**: Deploys to `deming.leedurbin.co.nz`
- **Build Environment**: Ubuntu with R, Quarto, and system dependencies
- **Deploy Method**: rsync over SSH to production server