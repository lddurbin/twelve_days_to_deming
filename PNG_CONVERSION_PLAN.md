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

#### 3.1 Template Utilization
**Existing Templates**: Use established templates in `assets/templates/`

**Available Templates:**
- `assets/templates/chapter-template.qmd` - Standard chapter structure with timing clocks, activities, and footnotes
- `assets/templates/activity-template.qmd` - Dedicated activity pages with download functionality

**Template Features Already Implemented:**
- Standard YAML frontmatter with execute settings
- R setup blocks with consistent function sourcing
- Column layouts for timing indicators (`create_clock()` integration)
- Interactive activity blocks with OJS inputs
- Collapsible commentary sections
- Download functionality for user notes
- Image integration with lightbox support
- Consistent styling classes (`.thought_commentary`, `.activity_afterthought`)

**Conversion Script Integration:**
The generation scripts should utilize these existing templates rather than creating new ones:

```python
# In scripts/generate-quarto-files.py
def select_template(content_type):
    if is_activity_page(content_type):
        return "assets/templates/activity-template.qmd"
    else:
        return "assets/templates/chapter-template.qmd"

def populate_template(template_path, extracted_content):
    # Replace template placeholders with extracted content
    # Maintain existing structure and styling
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

#### 4.1 Content Validation Pipeline ✅ COMPLETED
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

**Implementation Status:**
- ✅ Script created with comprehensive validation checks
- ✅ Command-line interface with --day and --strict options
- ✅ JSON output support for automated processing
- ✅ Tested on existing Day 1-2 content
- ✅ Usage examples created in `scripts/validate-day-example.sh`

#### 4.2 Quarto Integration ✅ COMPLETED
**File**: `scripts/update-quarto-config.py`

**Functionality:**
- Auto-update `_quarto.yml` with new chapters
- Generate chapter entries for Days 3-12
- Maintain consistent part/chapter structure
- Preserve existing theme and formatting

**Implementation Status:**
- ✅ Script created with comprehensive Quarto configuration management
- ✅ Command-line interface with --days, --dry-run, --validate-only options
- ✅ Automatic scanning of day directories for QMD files
- ✅ Chapter title extraction from YAML frontmatter
- ✅ Proper YAML formatting with backup creation
- ✅ Configuration validation and error handling
- ✅ Tested with existing Day 1-3 structure
- ✅ Usage examples created in `scripts/update-quarto-example.sh`

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
4. **`scripts/validate-conversion.py`** ✅ - Quality assurance and validation
5. **`scripts/update-quarto-config.py`** ✅ - Quarto configuration management

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
python scripts/validate-conversion.py --day $DAY --strict

echo "Day $DAY conversion complete!"
```

#### R Utilities
**File**: `R/functions/conversion-helpers.R`
- Content processing utilities
- Figure integration helpers
- Interactive element generators

## How to Use the Conversion System

### Fully Implemented Conversion Pipeline ✅

#### Core Conversion Tools
- ✅ **`scripts/extract-content.py`** - OCR and text extraction from PNG files using Tesseract
- ✅ **`scripts/extract-content-simple.py`** - Simplified text extraction
- ✅ **`scripts/extract-figures.py`** - Automated figure detection and extraction
- ✅ **`scripts/generate-quarto-files.py`** - Automated QMD file generation from extracted content

#### Analysis and Planning Tools
- ✅ **`scripts/analyze-day-content.sh`** - Extract page counts, titles, sections
- ✅ **`scripts/identify-figures.py`** - Detect charts, tables, images to extract
- ✅ **`scripts/map-interactive-elements.py`** - Identify activities, exercises

#### Validation and Quality Assurance
- ✅ **`scripts/validate-conversion.py`** - Comprehensive validation of converted content
- ✅ **`scripts/validate-day-example.sh`** - Example usage for day validation
- ✅ **`scripts/validate-figure-extraction.py`** - Specialized figure validation
- ✅ **`scripts/validate-interactive-elements.py`** - Interactive element validation

#### Quarto Configuration Management
- ✅ **`scripts/update-quarto-config.py`** - Auto-update _quarto.yml with new days
- ✅ **`scripts/update-quarto-example.sh`** - Example usage for config updates

#### Batch Processing Tools
- ✅ **`scripts/batch-extract-figures.sh`** - Batch figure extraction
- ✅ **`scripts/batch-generate-quarto.sh`** - Batch QMD generation

### Complete Automated Conversion Workflow ✅

#### Full Pipeline: PNG to Quarto

**1. Content Analysis and Planning**
```bash
# Analyze source PNG content structure
./scripts/analyze-day-content.sh 3

# Identify figures and interactive elements
python scripts/identify-figures.py --day 3 --source-dir 12-Days-to-Deming/PNGs/
python scripts/map-interactive-elements.py --day 3 --source-dir 12-Days-to-Deming/PNGs/
```

**2. Automated Content Extraction**
```bash
# Extract text content using OCR
python scripts/extract-content.py --day 3 --pages 005-020 --output temp/day-03-text/

# Alternative: simplified extraction
python scripts/extract-content-simple.py --day 3 --source-dir 12-Days-to-Deming/PNGs/

# Extract figures automatically
python scripts/extract-figures.py --day 3 --source-dir 12-Days-to-Deming/PNGs/ --output assets/images/day-03/
```

**3. Automated QMD Generation**
```bash
# Generate Quarto files from extracted content
python scripts/generate-quarto-files.py --day 3 --text-dir temp/day-03-text/ --output content/days/day-03/

# Batch processing (multiple days)
./scripts/batch-generate-quarto.sh 3-5
```

**4. Configuration and Validation**
```bash
# Update Quarto configuration
python scripts/update-quarto-config.py --days 3

# Comprehensive validation
python scripts/validate-conversion.py --day 3 --strict

# Specialized validation
python scripts/validate-figure-extraction.py --day 3
python scripts/validate-interactive-elements.py --day 3
```

**5. Complete Day Conversion (One Command)**
```bash
# Full pipeline for single day
./scripts/batch-extract-figures.sh 3
./scripts/batch-generate-quarto.sh 3
python scripts/validate-conversion.py --day 3 --strict
```

### Quality Control Checkpoints

#### 1. Automated Validation (✅ Available)
```bash
# Run comprehensive validation
python scripts/validate-conversion.py --day XX --strict

# Check specific components
python scripts/validate-figure-extraction.py --day XX
python scripts/validate-interactive-elements.py --day XX
```

**Automated Checks Include:**
- QMD file syntax and structure validation
- Image file existence and accessibility
- Interactive element functionality
- R code block validation
- YAML frontmatter correctness

#### 2. Manual Quality Review
- **Text Accuracy**: Compare transcribed content against source PNGs
- **Figure Quality**: Verify cropping boundaries and image clarity
- **Interactive Function**: Test all activities and download features
- **Styling Consistency**: Ensure consistent formatting across days

#### 3. Build Testing (✅ Automated in validation)
```bash
# The validation scripts automatically test:
# - quarto render compatibility
# - No build errors or warnings
# - All images load correctly
# - Navigation and interactivity work
```

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
- [x] Quality validation tools functional ✅
- [x] Quarto configuration management operational ✅
- [x] Documentation updated for current implementation ✅
- [x] OCR and content extraction tools ✅
- [x] Figure extraction automation ✅
- [x] Full automated conversion pipeline ✅

## Notes and Considerations

### System Status: FULLY OPERATIONAL ✅

**Pipeline Complete**: The full PNG-to-Quarto conversion system is implemented and ready for production use.

**Key Capabilities:**
- ✅ Automated OCR text extraction from PNG files
- ✅ Intelligent figure detection and extraction
- ✅ Template-based QMD file generation using existing `assets/templates/`
- ✅ Comprehensive validation and quality assurance
- ✅ Batch processing for multiple days
- ✅ Automated Quarto configuration management

**Quality Assurance Built-in:**
- Manual review checkpoints integrated
- Automated validation at each step
- Original source material preservation
- Continuous build testing

**Ready for Production:**
- Convert Days 3-12 using the implemented pipeline
- Scalable for future content additions
- Maintenance documentation complete
- Error handling and recovery built-in