# PNG to Quarto Conversion Plan

## Overview

This document outlines a systematic approach for converting the PNG source materials in `12-Days-to-Deming/PNGs/` into interactive Quarto pages, following the established patterns from Days 1 and 2.

## Current State Analysis

### Existing Structure
- **Days 1-2**: Fully implemented with interactive features
- **Source Material**: 44 PNG pages available (Day 2 content: pages 005-048)
- **File Pattern**: `E.Day.2.12Oct21_page_XXX.png` (2550x3300 resolution)
- **Issue**: Only Day 2 PNGs currently available, need Days 3-12 source materials

### Established Patterns (from Days 1-2)
- Modular QMD files with descriptive naming (`##-topic-name.qmd`)
- YAML frontmatter with title and execute settings
- R setup blocks with consistent function sourcing
- Interactive elements: timing clocks, activities, note downloads
- Image integration with lightbox functionality
- Consistent styling and formatting

## Implementation Plan

### Phase 1: Content Preparation

#### 1.1 Source Material Audit
```bash
# Check what PNG collections exist
ls 12-Days-to-Deming/PNGs/ | grep -o "Day\.[0-9]*" | sort -u

# Verify page counts per day
for day in {3..12}; do
  echo "Day $day: $(ls 12-Days-to-Deming/PNGs/ | grep "Day\.$day" | wc -l) pages"
done
```

**Action Items:**
- [ ] Verify PNG availability for Days 3-12
- [ ] If missing, convert original PDFs using existing workflow
- [ ] Organize files with standardized naming convention

#### 1.2 Create Analysis Tools
```bash
# Create scripts directory structure
mkdir -p scripts/conversion
mkdir -p templates
mkdir -p temp/analysis
```

**Scripts to Create:**
- `scripts/analyze-day-content.sh` - Extract page counts, titles, sections
- `scripts/identify-figures.py` - Detect charts, tables, images to extract
- `scripts/map-interactive-elements.py` - Identify activities, exercises

### Phase 2: Automated Content Extraction

#### 2.1 OCR and Text Extraction
**File**: `scripts/extract-content.py`

**Requirements:**
```bash
# Install dependencies
pip install pytesseract pillow opencv-python
```

**Functionality:**
- Use Tesseract OCR for text extraction from PNGs
- Post-process to handle formatting, equations, special characters
- Preserve heading structure and paragraph breaks
- Extract timing indicators and activity markers
- Handle multi-column layouts

**Command Structure:**
```bash
python scripts/extract-content.py --day 3 --pages 005-020 --output temp/day-03-text/
```

#### 2.2 Figure and Image Processing
**File**: `scripts/extract-figures.py`

**Functionality:**
- Automated detection of charts, tables, diagrams
- Intelligent cropping using image analysis
- Consistent naming: `assets/images/day-XX/figure-name.png`
- Generate alt text descriptions
- Batch processing with quality validation

**Command Structure:**
```bash
python scripts/extract-figures.py --day 3 --source-dir 12-Days-to-Deming/PNGs/ --output assets/images/day-03/
```

### Phase 3: Quarto File Generation

#### 3.1 Template Creation
**File**: `templates/day-template.qmd`

```yaml
---
title: "TEMPLATE_TITLE"
execute:
  echo: false
---

```{r}
# R setup for all chapters (edit as needed)
knitr::knit_hooks$set(crop = knitr::hook_pdfcrop)
source(here::here("R/functions/main-functions.R"))
```

TEMPLATE_CONTENT

<!-- Interactive elements -->
TEMPLATE_INTERACTIVE

<!-- Download functionality -->
TEMPLATE_DOWNLOAD
```

#### 3.2 Automated QMD Generation
**File**: `scripts/generate-quarto-files.py`

**Functionality:**
- Create QMD files based on extracted content
- Auto-generate YAML frontmatter
- Insert R setup blocks and function calls
- Structure content with consistent formatting
- Convert timing indicators to R function calls
- Generate interactive element blocks

**Command Structure:**
```bash
python scripts/generate-quarto-files.py --day 3 --text-dir temp/day-03-text/ --output content/days/day-03/
```

#### 3.3 Interactive Element Integration
**Functionality:**
- Identify "Pause for Thought" sections
- Generate OJS blocks for input forms
- Add download functionality for notes
- Convert timing indicators to `create_clock()` calls
- Integrate figure references with lightbox

### Phase 4: Quality Assurance and Integration

#### 4.1 Content Validation Pipeline
**File**: `scripts/validate-conversion.py`

**Validation Checks:**
- Compare OCR output accuracy against source images
- Verify all figures extracted and properly referenced
- Check Quarto syntax and R code blocks
- Validate interactive elements functionality
- Ensure consistent styling and formatting

**Command Structure:**
```bash
python scripts/validate-conversion.py --day 3 --strict
```

#### 4.2 Quarto Integration
**File**: `scripts/update-quarto-config.py`

**Functionality:**
- Auto-update `_quarto.yml` with new chapters
- Generate chapter entries for Days 3-12
- Maintain consistent part/chapter structure
- Preserve existing theme and formatting

## Implementation Tools

### Core Scripts

#### Main Orchestration
**File**: `scripts/day-converter.py`
```bash
# Convert entire day
python scripts/day-converter.py --day 3 --full-pipeline

# Convert with manual review checkpoints
python scripts/day-converter.py --day 3 --interactive
```

#### Individual Components
1. **`scripts/ocr-processor.py`** - Text extraction and cleaning
2. **`scripts/figure-extractor.py`** - Image processing and cropping
3. **`scripts/quarto-generator.py`** - QMD file creation
4. **`scripts/content-validator.py`** - Quality assurance

### Supporting Utilities

#### Batch Processing
**File**: `scripts/batch-convert-day.sh`
```bash
#!/bin/bash
# Process entire day at once
DAY=$1
echo "Converting Day $DAY..."

python scripts/extract-content.py --day $DAY
python scripts/extract-figures.py --day $DAY
python scripts/generate-quarto-files.py --day $DAY
python scripts/validate-conversion.py --day $DAY

echo "Day $DAY conversion complete!"
```

#### R Utilities
**File**: `R/functions/conversion-helpers.R`
- Content processing utilities
- Figure integration helpers
- Interactive element generators

## Workflow Integration

### Standard Conversion Process

#### Single Day Conversion
```bash
# 1. Convert single day
./scripts/convert-day.sh 3

# 2. Manual review and corrections
# Review generated files in content/days/day-03/

# 3. Validate conversion
./scripts/validate-day.sh 3

# 4. Test build
quarto render content/days/day-03/
```

#### Batch Conversion
```bash
# Convert range of days
./scripts/convert-days.sh 3-12

# Validate all
for day in {3..12}; do
  ./scripts/validate-day.sh $day
done
```

### Quality Control Checkpoints

#### 1. Text Accuracy Review
- **Manual Step**: Compare OCR output against source images
- **Focus Areas**: Mathematical equations, special characters, formatting
- **Tool**: Side-by-side comparison viewer

#### 2. Figure Extraction Validation
- **Check**: All charts/tables captured correctly
- **Verify**: Proper cropping boundaries and image quality
- **Ensure**: Consistent naming and alt text

#### 3. Interactive Elements Testing
- **Test**: All activities and timing indicators
- **Verify**: Download functionality works
- **Check**: OJS blocks render correctly

#### 4. Build Validation
- **Command**: `quarto render`
- **Check**: No errors or warnings
- **Verify**: All images load correctly
- **Test**: Navigation and interactivity

## Development Priority

### Recommended Implementation Order

#### Phase 1: Prototype Development (Day 3)
1. **Week 1**: Build core extraction scripts
   - OCR text extraction
   - Basic figure detection
   - Simple QMD generation

2. **Week 2**: Refine and test on Day 3
   - Manual corrections and improvements
   - Quality validation
   - Interactive element integration

#### Phase 2: System Refinement
3. **Week 3**: Optimize automation
   - Improve OCR accuracy
   - Enhance figure extraction
   - Streamline QMD generation

4. **Week 4**: Validation and testing
   - Comprehensive quality checks
   - Build and render testing
   - Documentation and workflows

#### Phase 3: Scale-Up (Days 4-12)
5. **Weeks 5-8**: Batch processing
   - Apply refined system to remaining days
   - Continuous quality monitoring
   - Final integration and testing

## Success Criteria

### Technical Requirements
- [ ] All Days 3-12 converted to QMD format
- [ ] Consistent with existing Days 1-2 patterns
- [ ] All figures properly extracted and referenced
- [ ] Interactive elements functional
- [ ] Clean `quarto render` build

### Content Quality Standards
- [ ] Exact transcription of original content (per CLAUDE.md requirements)
- [ ] Preserved pedagogical flow and structure
- [ ] Enhanced with appropriate interactive elements
- [ ] Consistent timing indicators and activities
- [ ] Professional presentation quality

### Workflow Efficiency
- [ ] Automated conversion pipeline operational
- [ ] Quality validation tools functional
- [ ] Documentation complete for future maintenance
- [ ] Scalable for additional content updates

## Notes and Considerations

### Current Limitations
- Only Day 2 PNGs currently available
- OCR accuracy may require manual correction
- Complex figures might need manual cropping refinement
- Interactive elements require careful integration

### Risk Mitigation
- Start with single day prototype
- Build in manual review checkpoints
- Maintain backup of original source materials
- Test frequently with `quarto render`

### Future Enhancements
- Improved OCR training for mathematical content
- Advanced figure detection algorithms
- Automated interactive element recognition
- Content versioning and update workflows