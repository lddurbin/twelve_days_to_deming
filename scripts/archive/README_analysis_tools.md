# PNG Analysis Tools

This directory contains tools for analyzing PNG files from the "12 Days to Deming" project to prepare for Quarto conversion.

## Overview

The analysis tools are designed to:
1. Extract page counts, titles, and sections from PNG files
2. Detect charts, tables, and images for extraction
3. Identify activities, exercises, and interactive elements

## Tools

### 1. analyze-day-content.sh

**Purpose**: Extract basic information about PNG files for a specific day.

**Usage**:
```bash
./scripts/analyze-day-content.sh <day_number> [output_dir]
```

**Example**:
```bash
./scripts/analyze-day-content.sh 3 temp/analysis
```

**Output**:
- `day-{N}-analysis.txt` - Human-readable analysis report
- `day-{N}-summary.json` - JSON summary for programmatic use
- `day-{N}-pages.csv` - CSV file with page numbers and filenames

### 2. extract-content-simple.py

**Purpose**: Extract text content from PNG files using OCR (Tesseract).

**Requirements**:
```bash
# Install Tesseract OCR
brew install tesseract

# Install Python dependencies
pip install pytesseract pillow opencv-python
```

**Usage**:
```bash
python scripts/extract-content-simple.py --day 3 --pages 001-003 --output temp/day-03-text/
```

**Output**:
- `day-{N}-raw-text.txt` - Raw OCR text extraction
- `day-{N}-processed-text.txt` - Processed text with line classification
- `day-{N}-summary.txt` - Summary of extracted content

**Features**:
- OCR text extraction using Tesseract
- Line classification (headings, paragraphs, list items)
- Timing indicator detection
- Activity indicator detection
- Text preprocessing for better OCR results

### 3. identify-figures.py

**Purpose**: Detect charts, tables, and images in PNG files using computer vision.

**Requirements**:
```bash
pip install -r scripts/requirements.txt
```

**Usage**:
```bash
python scripts/identify-figures.py --day 3 --source-dir 12-Days-to-Deming/PNGs/ --output temp/analysis
```

**Output**:
- `day-{N}-figures.json` - Detailed analysis of detected figures

**Features**:
- Rectangle detection for figures
- Text region detection for tables
- Chart detection using line analysis
- Region classification and deduplication

### 4. map-interactive-elements.py

**Purpose**: Identify activities, exercises, and interactive elements in PNG files.

**Usage**:
```bash
python scripts/map-interactive-elements.py --day 3 --source-dir 12-Days-to-Deming/PNGs/ --output temp/analysis
```

**Output**:
- `day-{N}-interactive-elements.json` - Analysis of interactive elements

**Features**:
- Text region detection
- Highlighted region detection
- Box and border detection
- Icon and symbol detection
- Interactive element classification

## Directory Structure

```
scripts/
├── analyze-day-content.sh          # Basic PNG analysis
├── extract-content-simple.py       # OCR text extraction
├── identify-figures.py             # Figure detection
├── map-interactive-elements.py     # Interactive element mapping
├── requirements.txt                # Python dependencies
└── README_analysis_tools.md        # This file

temp/analysis/                      # Output directory
├── day-{N}-analysis.txt           # Analysis reports
├── day-{N}-summary.json           # JSON summaries
├── day-{N}-pages.csv              # CSV page lists
├── day-{N}-figures.json           # Figure analysis
└── day-{N}-interactive-elements.json # Interactive element analysis

temp/day-{N}-text/                 # OCR extraction output
├── day-{N}-raw-text.txt           # Raw OCR text
├── day-{N}-processed-text.txt     # Processed text with classification
└── day-{N}-summary.txt            # OCR extraction summary
```

## Usage Examples

### Analyze a single day
```bash
# Basic analysis
./scripts/analyze-day-content.sh 3

# OCR text extraction
python scripts/extract-content-simple.py --day 3 --pages 001-010

# Figure detection
python scripts/identify-figures.py --day 3

# Interactive element mapping
python scripts/map-interactive-elements.py --day 3
```

### Batch analysis
```bash
# Analyze multiple days
for day in {3..12}; do
    echo "Analyzing Day $day..."
    ./scripts/analyze-day-content.sh $day
    python scripts/extract-content-simple.py --day $day --pages 001-010
    python scripts/identify-figures.py --day $day
    python scripts/map-interactive-elements.py --day $day
done
```

## Output Format

### JSON Structure
```json
{
  "day": 3,
  "total_pages": 66,
  "analysis_timestamp": "2025-09-26T22:16:50Z",
  "pages": [
    {
      "filename": "F.Day.3.13Jan20_page_001.png",
      "page_number": 1,
      "dimensions": {"width": 2550, "height": 3300},
      "figures": {
        "rectangles": 2,
        "text_regions": 1,
        "charts": 0,
        "total_unique": 3
      },
      "regions": [
        {
          "type": "figure",
          "bbox": {"x": 100, "y": 200, "width": 800, "height": 600},
          "area": 480000,
          "center": {"x": 500, "y": 500}
        }
      ]
    }
  ]
}
```

## Dependencies

### System Requirements
- Python 3.7+
- OpenCV
- NumPy
- Pandas
- Pillow

### Installation
```bash
pip install -r scripts/requirements.txt
```

## Notes

- All scripts are designed to work with the existing project structure
- Output files are saved in the `temp/analysis/` directory
- Analysis results can be used by subsequent conversion tools
- The tools are designed to be run independently or as part of a pipeline

## Troubleshooting

### Common Issues

1. **Missing dependencies**: Install required Python packages
2. **File permissions**: Ensure scripts are executable (`chmod +x`)
3. **Path issues**: Run scripts from the project root directory
4. **Memory issues**: Large PNG files may require significant memory

### Error Messages

- "No PNG files found": Check that PNG files exist in the source directory
- "Could not load image": Verify PNG file integrity
- "Permission denied": Check file permissions and execute permissions
