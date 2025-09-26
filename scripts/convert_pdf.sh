#!/bin/bash

# Simple wrapper script for PDF to PNG conversion
# Usage: ./convert_pdf.sh <input_pdf> [output_dir] [--single] [--alt]

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
R_SCRIPT="$SCRIPT_DIR/pdf_to_png_converter.R"

# Check if R script exists
if [ ! -f "$R_SCRIPT" ]; then
    echo "Error: R script not found at $R_SCRIPT"
    exit 1
fi

# Run the R script with all arguments
Rscript "$R_SCRIPT" "$@" 