#!/bin/bash

# analyze-day-content.sh
# Extract page counts, titles, sections from PNG files for a specific day
# Usage: ./analyze-day-content.sh <day_number> [output_dir]

set -e

# Check arguments
if [ $# -lt 1 ]; then
    echo "Usage: $0 <day_number> [output_dir]"
    echo "Example: $0 3 temp/analysis"
    exit 1
fi

DAY=$1
OUTPUT_DIR=${2:-"temp/analysis"}
PNG_DIR="12-Days-to-Deming/PNGs"

# Create output directory if it doesn't exist
mkdir -p "$OUTPUT_DIR"

# Find the PNG files for the specified day
PNG_FILES=$(ls "$PNG_DIR" | grep "Day\.$DAY" | sort)

if [ -z "$PNG_FILES" ]; then
    echo "Error: No PNG files found for Day $DAY"
    exit 1
fi

# Count total pages
TOTAL_PAGES=$(echo "$PNG_FILES" | wc -l)
echo "Day $DAY Analysis Report" > "$OUTPUT_DIR/day-${DAY}-analysis.txt"
echo "=========================" >> "$OUTPUT_DIR/day-${DAY}-analysis.txt"
echo "Total pages: $TOTAL_PAGES" >> "$OUTPUT_DIR/day-${DAY}-analysis.txt"
echo "PNG files found: $(echo "$PNG_FILES" | wc -l)" >> "$OUTPUT_DIR/day-${DAY}-analysis.txt"
echo "" >> "$OUTPUT_DIR/day-${DAY}-analysis.txt"

# Extract page ranges
FIRST_PAGE=$(echo "$PNG_FILES" | head -1 | grep -o 'page_[0-9]*' | sed 's/page_//')
LAST_PAGE=$(echo "$PNG_FILES" | tail -1 | grep -o 'page_[0-9]*' | sed 's/page_//')

echo "Page range: $FIRST_PAGE to $LAST_PAGE" >> "$OUTPUT_DIR/day-${DAY}-analysis.txt"
echo "" >> "$OUTPUT_DIR/day-${DAY}-analysis.txt"

# List all PNG files
echo "PNG Files:" >> "$OUTPUT_DIR/day-${DAY}-analysis.txt"
echo "----------" >> "$OUTPUT_DIR/day-${DAY}-analysis.txt"
echo "$PNG_FILES" >> "$OUTPUT_DIR/day-${DAY}-analysis.txt"
echo "" >> "$OUTPUT_DIR/day-${DAY}-analysis.txt"

# Create a JSON summary for programmatic use
cat > "$OUTPUT_DIR/day-${DAY}-summary.json" << EOF
{
  "day": $DAY,
  "total_pages": $TOTAL_PAGES,
  "page_range": {
    "first": $FIRST_PAGE,
    "last": $LAST_PAGE
  },
  "png_files": [
$(echo "$PNG_FILES" | sed 's/^/    "/' | sed 's/$/",/' | sed '$s/,$//')
  ],
  "analysis_timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
}
EOF

# Create a CSV file for easy import
echo "page_number,filename" > "$OUTPUT_DIR/day-${DAY}-pages.csv"
echo "$PNG_FILES" | while read -r file; do
    page_num=$(echo "$file" | grep -o 'page_[0-9]*' | sed 's/page_//')
    echo "$page_num,$file" >> "$OUTPUT_DIR/day-${DAY}-pages.csv"
done

echo "Analysis complete for Day $DAY"
echo "Output files:"
echo "  - $OUTPUT_DIR/day-${DAY}-analysis.txt"
echo "  - $OUTPUT_DIR/day-${DAY}-summary.json"
echo "  - $OUTPUT_DIR/day-${DAY}-pages.csv"
