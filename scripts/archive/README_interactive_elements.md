# Interactive Element Integration System

This document describes the interactive element integration system implemented as Phase 3.3 of the PNG to Quarto Conversion Plan.

## Overview

The interactive element integration system automatically detects, generates, and validates interactive elements in Quarto QMD files. It provides intelligent detection of "Pause for Thought" sections, OJS input generation, download functionality, timing indicators, and lightbox integration.

## Components

### Core Scripts

#### 1. Enhanced `generate-quarto-files.py`
The main QMD generation script now includes advanced interactive element features:

**New Interactive Features:**
- **Interactive Section Detection**: Automatically identifies "Pause for Thought", "Your Turn", and other interactive content
- **OJS Input Generation**: Creates proper OJS blocks with textarea inputs
- **Download Functionality**: Adds download buttons and triggers for note-taking
- **Timing Indicator Conversion**: Converts timing text to `create_clock()` R function calls
- **Lightbox Integration**: Integrates figure references with lightbox functionality
- **Activity Classification**: Distinguishes between regular chapters and activity pages

**Enhanced Detection Patterns:**
```python
# Interactive element patterns
self.interactive_patterns = [
    r"pause for thought",
    r"your turn", 
    r"think about",
    r"consider",
    r"reflect",
    r"discuss",
    r"write",
    r"note",
    r"comment"
]

# Download patterns
self.download_patterns = [
    r"download",
    r"save", 
    r"export",
    r"notes",
    r"workbook"
]
```

#### 2. `validate-interactive-elements.py`
Comprehensive validation script for interactive elements:

**Validation Features:**
- **OJS Block Validation**: Checks for proper Inputs.textarea and viewof variables
- **Collapse Button Validation**: Ensures button targets match collapse divs
- **Download Functionality Validation**: Verifies download buttons and triggers
- **Timing Indicator Validation**: Validates create_clock() parameters
- **Figure Reference Validation**: Checks lightbox integration and alt text
- **File Structure Validation**: Validates YAML frontmatter and R setup blocks

#### 3. `batch-generate-quarto.sh`
Batch processing script for multiple days:

**Features:**
- Automated virtual environment setup
- Batch processing of day ranges
- Optional figure integration
- Summary report generation
- Progress tracking

### Interactive Element Types

#### 1. Pause for Thought Sections
Automatically detected and converted to interactive blocks:

```markdown
<div class=thought_commentary>

## PAUSE FOR THOUGHT

Consider what you know about variation.

```{ojs}
viewof interactive_1 = Inputs.textarea({placeholder: "Type your comments here.", rows: 15})
```

<button class="btn btn-primary" type="button" data-bs-toggle="collapse" data-bs-target="#collapse_interactive_1" aria-expanded="false" aria-controls="collapse_interactive_1">
Show Commentary
</button>

<div class="collapse" id="collapse_interactive_1">
Optional commentary to be revealed after completing the activity.
</div>
</div>
```

#### 2. Activity Pages
Full activity pages with download functionality:

```markdown
---
title: "ACTIVITY TITLE"
execute:
  echo: false
---

```{r}
# R setup for all activities
knitr::knit_hooks$set(crop = knitr::hook_pdfcrop)
source(here::here("R/functions/main-functions.R"))
```

# Activity Heading

Activity content here.

```{ojs}
viewof activity_id = Inputs.textarea({placeholder: "Type your comments here.", rows: 10})
```

<button class="btn btn-primary" type="button" data-bs-toggle="collapse" data-bs-target="#collapse_feedback" aria-expanded="false" aria-controls="collapse_feedback">
Show Commentary
</button>
<div class="collapse" id="collapse_feedback">
Activity feedback or commentary goes here.
</div>

<div class=activity_afterthought>Optional afterthought or tip.</div>

```{ojs download_all}
// Download button element
download_button = html`<button class="btn btn-primary" type="button">Download Your Notes</button>`
```

```{ojs download_trigger}
//| output: false
import { downloadNotes } from "/assets/scripts/functions.js"
download_button.onclick = () => {
  downloadNotes([viewof activity_id], "activity_notes.txt");
};
```
```

#### 3. Timing Indicators
Automatically converted to R function calls:

```markdown
:::: {.columns}
::: {.column width="85%"}
Content with timing indicator.
:::
::: {.column width="15%"}
<div style="margin-top: 10px">
```{r, echo=FALSE, message=FALSE, warning=FALSE}
create_clock(15, 00)
```
</div>
:::
::::
```

#### 4. Figure Integration
Automatic lightbox integration:

```markdown
![Figure description](assets/images/day-03-extracted/day-03-page-005-chart-00.png){.lightbox}
```

## Usage Workflow

### Single Day Processing
```bash
# 1. Generate QMD files with interactive elements
python scripts/generate-quarto-files.py --day 3 --text-dir temp/day-03-text/ --output content/days/day-03/ --figures-dir assets/images/day-03-extracted/

# 2. Validate interactive elements
python scripts/validate-interactive-elements.py --day 3 --content-dir content/days/day-03/

# 3. Review generated files and validation results
ls content/days/day-03/
cat content/days/day-03/day-03-interactive-validation.json
```

### Batch Processing
```bash
# Process multiple days
./scripts/batch-generate-quarto.sh 3-12

# Review summary
cat temp/quarto-generation-summary.json
```

## Validation Results

### Validation Summary
The validation script provides comprehensive feedback:

```json
{
  "day": 3,
  "validation_timestamp": "2025-09-27T15:37:20.880000",
  "summary": {
    "total_files": 5,
    "total_issues": 9,
    "files_with_issues": 4
  },
  "file_validations": [
    {
      "file": "content/days/day-03/03-introduction-to-the-funnel-experiment.qmd",
      "total_issues": 0,
      "issues": []
    }
  ]
}
```

### Issue Types
- **Error**: Critical issues that prevent functionality
- **Warning**: Issues that may affect user experience
- **Info**: Informational messages about content

### Common Issues and Solutions

#### Missing OJS Blocks
- **Issue**: No OJS blocks found in content
- **Solution**: Ensure content contains interactive keywords or manually add OJS blocks

#### Mismatched Collapse Targets
- **Issue**: Button targets don't match collapse div IDs
- **Solution**: Check that `data-bs-target` values match `id` attributes in collapse divs

#### Incomplete Download Functionality
- **Issue**: Download button without trigger or vice versa
- **Solution**: Ensure both `download_all` and `download_trigger` OJS blocks are present

#### Invalid Timing Parameters
- **Issue**: Invalid hour or minute values in create_clock()
- **Solution**: Check that hours are 0-23 and minutes are 0-59

## Configuration

### Detection Thresholds
- **Interactive Patterns**: Configurable regex patterns for detecting interactive content
- **Download Patterns**: Patterns that trigger download functionality
- **Activity Patterns**: Patterns that classify content as activities

### Template Selection
- **Chapter Template**: Used for regular content with basic interactive elements
- **Activity Template**: Used for full activity pages with download functionality

### Content Enhancement
- **Timing Conversion**: Automatic conversion of timing text to R function calls
- **Figure Integration**: Automatic lightbox class addition to image references
- **Interactive Block Generation**: Automatic OJS block generation for detected content

## Integration with Existing System

### Template Integration
The system uses existing templates from `assets/templates/`:
- `chapter-template.qmd` - Standard chapter structure
- `activity-template.qmd` - Activity pages with download functionality

### Figure Integration
Works with Phase 2.2 figure extraction results:
- Automatic figure reference generation
- Lightbox class integration
- Alt text preservation

### Content Integration
Processes Phase 2.1 extracted content:
- JSON format support
- Line-by-line processing
- Content type detection

## Troubleshooting

### Common Issues

#### Interactive Elements Not Detected
- **Symptom**: No OJS blocks generated
- **Solution**: Check that content contains interactive keywords or adjust detection patterns

#### Download Functionality Not Working
- **Symptom**: Download buttons don't work
- **Solution**: Ensure `functions.js` is properly loaded and downloadNotes function exists

#### Timing Indicators Not Converted
- **Symptom**: Timing text not converted to create_clock() calls
- **Solution**: Check timing pattern regex and ensure proper format (HH:MM or minutes)

#### Validation Errors
- **Symptom**: Multiple validation errors
- **Solution**: Review validation results and fix critical issues first

### Performance Optimization

#### Large Content Processing
- Process days individually for better error handling
- Monitor memory usage for large content files
- Use batch processing for efficiency

#### Validation Optimization
- Run validation after content generation
- Focus on critical issues first
- Use validation results to improve content quality

## Future Enhancements

### Planned Improvements
- Advanced interactive element recognition
- Custom interactive element types
- Enhanced validation rules
- Integration with Quarto document generation pipeline
- Web interface for manual review and correction

### Extensibility
The system is designed to be easily extensible:
- Add new detection patterns by modifying regex lists
- Customize interactive block generation by extending generation methods
- Enhance validation by adding new validation functions
- Integrate with other phases of the conversion pipeline

## Support and Maintenance

### Logging
All scripts provide detailed logging for troubleshooting:
- Processing progress and timing
- Error messages and warnings
- Validation results and recommendations

### Backup and Recovery
- Always maintain backups of generated QMD files
- Validation results provide audit trail for quality assurance
- Use version control for tracking changes

### Updates and Maintenance
- Regularly update detection patterns based on content analysis
- Monitor validation results and adjust rules as needed
- Review and update interactive element templates
- Test with new content types and formats
