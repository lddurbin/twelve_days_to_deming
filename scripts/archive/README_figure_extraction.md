# Figure Extraction System

This document describes the automated figure extraction system implemented as Phase 2.2 of the PNG to Quarto Conversion Plan.

## Overview

The figure extraction system automatically detects, extracts, and processes charts, tables, diagrams, and other visual elements from PNG source materials. It provides intelligent cropping, quality enhancement, and consistent naming for integration into Quarto documents.

## Components

### Core Scripts

#### 1. `extract-figures.py`
Main figure extraction script that processes PNG files and extracts visual elements.

**Features:**
- Advanced figure detection using multiple techniques (contours, edges, color analysis, template matching)
- Intelligent cropping with quality enhancement
- Consistent naming convention: `day-XX-page-XXX-type-XX.png`
- Automatic alt text generation for accessibility
- Quality scoring and validation
- Batch processing capabilities

**Usage:**
```bash
python scripts/extract-figures.py --day 3 --source-dir 12-Days-to-Deming/PNGs/ --output assets/images/day-03/
```

**Parameters:**
- `--day`: Day number to process
- `--source-dir`: Source directory for PNG files
- `--output`: Output directory for extracted figures
- `--min-area`: Minimum figure area in pixels (default: 15000)
- `--min-width`: Minimum figure width in pixels (default: 200)
- `--min-height`: Minimum figure height in pixels (default: 150)

#### 2. `validate-figure-extraction.py`
Quality validation script that checks extraction results for completeness and quality.

**Features:**
- File integrity validation
- Image quality analysis (sharpness, contrast, brightness)
- Naming convention validation
- Metadata completeness checks
- Automated recommendations for improvement

**Usage:**
```bash
python scripts/validate-figure-extraction.py --day 2 --results-dir assets/images/day-02-extracted/
```

#### 3. `batch-extract-figures.sh`
Batch processing script for processing multiple days at once.

**Features:**
- Automated virtual environment setup
- Batch processing of day ranges
- Summary report generation
- Progress tracking

**Usage:**
```bash
./scripts/batch-extract-figures.sh 3-12
./scripts/batch-extract-figures.sh 3
```

### Supporting Scripts

#### `identify-figures.py`
Figure detection and analysis script (Phase 2.1) that identifies potential figures without extraction.

## Installation and Setup

### Prerequisites
- Python 3.7+
- OpenCV (opencv-python)
- NumPy
- Pillow
- Other dependencies listed in `requirements.txt`

### Setup
```bash
# Create virtual environment
python3 -m venv venv
source venv/bin/activate

# Install dependencies
pip install -r scripts/requirements.txt
```

## Usage Workflow

### Single Day Processing
```bash
# 1. Extract figures
python scripts/extract-figures.py --day 3 --source-dir 12-Days-to-Deming/PNGs/ --output assets/images/day-03/

# 2. Validate results
python scripts/validate-figure-extraction.py --day 3 --results-dir assets/images/day-03/

# 3. Review extracted figures and results
ls assets/images/day-03/
cat assets/images/day-03/day-03-extraction-results.json
```

### Batch Processing
```bash
# Process multiple days
./scripts/batch-extract-figures.sh 3-12

# Review summary
cat temp/figure-extraction-summary.json
```

## Output Structure

### Directory Layout
```
assets/images/day-XX-extracted/
├── day-XX-page-XXX-chart-00.png
├── day-XX-page-XXX-table-00.png
├── day-XX-page-XXX-diagram-00.png
├── day-XX-extraction-results.json
└── day-XX-validation-results.json
```

### Results Files

#### `day-XX-extraction-results.json`
Contains detailed information about the extraction process:
```json
{
  "day": 2,
  "total_pages": 44,
  "processing_timestamp": "2025-09-27T11:39:45.316411",
  "output_directory": "assets/images/day-02-extracted",
  "pages": [
    {
      "source_file": "E.Day.2.12Oct21_page_005.png",
      "page_number": 5,
      "figures_detected": 1,
      "figures_extracted": 1,
      "extracted_figures": [
        {
          "filename": "day-02-page-005-table-00.png",
          "filepath": "assets/images/day-02-extracted/day-02-page-005-table-00.png",
          "type": "table",
          "bbox": [1389, 1266, 947, 264],
          "area": 250008,
          "quality_score": 0.11197894236143195,
          "alt_text": "Data table with structured information, area: 250008 pixels",
          "method": "edge",
          "confidence": 0.028519087389203546
        }
      ]
    }
  ]
}
```

#### `day-XX-validation-results.json`
Contains validation results and quality analysis:
```json
{
  "day": 2,
  "validation_timestamp": "2025-09-27T11:42:31.847000",
  "summary": {
    "total_pages": 44,
    "total_figures": 56,
    "file_issues": 0,
    "quality_issues": 38,
    "naming_issues": 0,
    "metadata_issues": 0
  },
  "issues": {
    "file_integrity": [],
    "quality": [...],
    "naming_convention": [],
    "metadata_completeness": []
  },
  "recommendations": [...]
}
```

## Figure Types

The system classifies extracted figures into the following types:

- **chart**: Data visualizations with lines, axes, and plotted data
- **table**: Structured data in tabular format
- **diagram**: Flowcharts, process diagrams, and conceptual illustrations
- **figure**: General visual content and images
- **image**: Photographs and other raster images

## Quality Metrics

### Detection Methods
- **contour**: Based on shape analysis and contour detection
- **edge**: Based on edge density and line detection
- **color**: Based on color region analysis
- **template**: Based on template matching for common patterns

### Quality Scores
- **Sharpness**: Laplacian variance (higher is better)
- **Contrast**: Standard deviation of pixel values (higher is better)
- **Brightness**: Mean pixel value (optimal range: 30-225)

## Configuration

### Detection Thresholds
- `min_figure_area`: Minimum area for figure detection (default: 15000 pixels)
- `min_figure_width`: Minimum width (default: 200 pixels)
- `min_figure_height`: Minimum height (default: 150 pixels)
- `max_figure_ratio`: Maximum ratio of figure to page size (default: 0.8)

### Enhancement Settings
- `contrast_factor`: Contrast enhancement multiplier (default: 1.2)
- `sharpness_factor`: Sharpness enhancement multiplier (default: 1.1)

## Troubleshooting

### Common Issues

#### Low Figure Detection Rate
- **Symptom**: Few figures detected per page
- **Solution**: Lower `--min-area`, `--min-width`, or `--min-height` thresholds
- **Example**: `--min-area 5000 --min-width 100 --min-height 100`

#### High False Positive Rate
- **Symptom**: Too many small or irrelevant regions detected
- **Solution**: Increase minimum size thresholds
- **Example**: `--min-area 20000 --min-width 300 --min-height 200`

#### Poor Image Quality
- **Symptom**: Validation reports low sharpness or contrast
- **Solution**: Adjust enhancement parameters in the script
- **Note**: May require manual review of source images

#### Missing Dependencies
- **Symptom**: Import errors for cv2, numpy, etc.
- **Solution**: Ensure virtual environment is activated and dependencies installed
- **Command**: `source venv/bin/activate && pip install -r scripts/requirements.txt`

### Performance Optimization

#### Large Batch Processing
- Process days individually for better error handling
- Monitor disk space for large output directories
- Consider processing during off-peak hours

#### Memory Usage
- The script processes images one at a time to minimize memory usage
- For very large images, consider resizing source PNGs first

## Integration with Quarto

### File References
Extracted figures can be referenced in Quarto documents using:
```markdown
![Alt text](assets/images/day-02-extracted/day-02-page-005-table-00.png)
```

### Lightbox Integration
For interactive viewing, use Quarto's lightbox functionality:
```markdown
::: {.glightbox}
![Alt text](assets/images/day-02-extracted/day-02-page-005-table-00.png)
:::
```

### Metadata Integration
Use the extraction results JSON to automatically generate figure captions and references in Quarto documents.

## Future Enhancements

### Planned Improvements
- OCR integration for figure captions and labels
- Automatic figure numbering and cross-referencing
- Advanced template matching for specific figure types
- Integration with Quarto document generation pipeline
- Web interface for manual review and correction

### Extensibility
The system is designed to be easily extensible:
- Add new detection methods by implementing additional `_detect_by_*` methods
- Customize figure classification by modifying `_classify_figure_type`
- Enhance quality metrics by extending `_calculate_quality_score`
- Add new validation checks by implementing additional validation methods

## Support and Maintenance

### Logging
All scripts provide detailed logging for troubleshooting:
- Processing progress and timing
- Error messages and warnings
- Quality metrics and validation results

### Backup and Recovery
- Always maintain backups of original PNG source files
- Extraction results are stored in JSON format for easy recovery
- Validation results provide audit trail for quality assurance

### Updates and Maintenance
- Regularly update dependencies for security and performance
- Monitor extraction quality and adjust thresholds as needed
- Review and update figure classification rules based on content analysis
