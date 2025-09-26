# PDF to PNG Converter

This directory contains scripts to convert PDF files to PNG images, specifically designed for the "12 Days to Deming" project.

## Files

- `pdf_to_png_converter.R` - Main R script for PDF to PNG conversion
- `convert_pdf.sh` - Shell wrapper script for easier usage
- `README_pdf_converter.md` - This documentation file

## Requirements

The script requires the following R packages:
- `pdftools` - For PDF manipulation
- `magick` - For image processing

These will be automatically installed if not already present.

## Usage

### Method 1: Using the shell wrapper (recommended)

```bash
# Convert each page to individual PNG files (default method)
./scripts/convert_pdf.sh 12-Days-to-Deming/PDFs/E.Day.2.12Oct21.pdf

# Use alternative conversion method (more reliable)
./scripts/convert_pdf.sh 12-Days-to-Deming/PDFs/E.Day.2.12Oct21.pdf --alt

# Specify custom output directory
./scripts/convert_pdf.sh 12-Days-to-Deming/PDFs/E.Day.2.12Oct21.pdf custom/output/dir

# Convert to a single PNG file (all pages combined)
./scripts/convert_pdf.sh 12-Days-to-Deming/PDFs/E.Day.2.12Oct21.pdf --single

# Set custom DPI
./scripts/convert_pdf.sh 12-Days-to-Deming/PDFs/E.Day.2.12Oct21.pdf --dpi=150
```

### Method 2: Direct R script execution

```bash
# Convert each page to individual PNG files (default method)
Rscript scripts/pdf_to_png_converter.R 12-Days-to-Deming/PDFs/E.Day.2.12Oct21.pdf

# Use alternative conversion method (more reliable)
Rscript scripts/pdf_to_png_converter.R 12-Days-to-Deming/PDFs/E.Day.2.12Oct21.pdf --alt

# Specify custom output directory
Rscript scripts/pdf_to_png_converter.R 12-Days-to-Deming/PDFs/E.Day.2.12Oct21.pdf 12-Days-to-Deming/PNGs

# Convert to a single PNG file
Rscript scripts/pdf_to_png_converter.R 12-Days-to-Deming/PDFs/E.Day.2.12Oct21.pdf --single

# Set custom DPI
Rscript scripts/pdf_to_png_converter.R 12-Days-to-Deming/PDFs/E.Day.2.12Oct21.pdf --dpi=150
```

### Method 3: Interactive R usage

```r
# Source the script in R
source("scripts/pdf_to_png_converter.R")

# Convert PDF to individual PNG files (default method)
convert_pdf_to_png("12-Days-to-Deming/PDFs/E.Day.2.12Oct21.pdf")

# Use alternative conversion method (more reliable)
convert_pdf_to_png_alt("12-Days-to-Deming/PDFs/E.Day.2.12Oct21.pdf")

# Convert PDF to single PNG file
convert_pdf_to_single_png("12-Days-to-Deming/PDFs/E.Day.2.12Oct21.pdf")
```

## Options

- `--single`: Convert all pages to a single PNG file instead of individual files
- `--alt`: Use alternative conversion method (`pdf_convert`) which is more reliable
- `--dpi=N`: Set the DPI (dots per inch) for the output images (default: 300)

## Conversion Methods

### Default Method (`pdf_render_page`)
- Uses `pdf_render_page` function from `pdftools`
- Converts each page individually
- May have issues with certain PDF formats

### Alternative Method (`--alt` flag)
- Uses `pdf_convert` function from `pdftools`
- More reliable and robust
- Recommended for most PDF files
- **This is the default method when running without arguments**

## Output

### Individual page mode (default)
- Creates separate PNG files for each page
- Naming convention: `{original_name}_page_001.png`, `{original_name}_page_002.png`, etc.
- Example: `E.Day.2.12Oct21_page_001.png`, `E.Day.2.12Oct21_page_002.png`

### Single file mode (`--single`)
- Creates one PNG file containing all pages
- Naming convention: `{original_name}.png`
- Example: `E.Day.2.12Oct21.png`

## Default Output Directory

If no output directory is specified, files are saved to:
```
12-Days-to-Deming/PNGs/
```

## Example

For the file `12-Days-to-Deming/PDFs/E.Day.2.12Oct21.pdf`:

```bash
# Recommended: Use alternative method
./scripts/convert_pdf.sh 12-Days-to-Deming/PDFs/E.Day.2.12Oct21.pdf --alt
```

This will create:
- `12-Days-to-Deming/PNGs/E.Day.2.12Oct21_page_001.png`
- `12-Days-to-Deming/PNGs/E.Day.2.12Oct21_page_002.png`
- `12-Days-to-Deming/PNGs/E.Day.2.12Oct21_page_003.png`
- ... (one file per page)

## Troubleshooting

### "The 'image' argument is not a magick image object" Error
If you encounter this error, try using the alternative method:
```bash
./scripts/convert_pdf.sh your_file.pdf --alt
```

### General Issues
1. **Use the `--alt` flag** - The alternative method is more reliable
2. **Check file permissions** - Ensure the script has read access to the PDF
3. **Verify PDF integrity** - Make sure the PDF file is not corrupted
4. **Try lower DPI** - Use `--dpi=150` or `--dpi=72` for faster processing

## Error Handling

The script includes error handling for:
- Missing input files
- Invalid file paths
- PDF processing errors
- Image saving errors

Each page conversion is wrapped in a try-catch block, so if one page fails, the others will still be processed.

## Notes

- The script automatically creates output directories if they don't exist
- High DPI settings (300+) will produce larger, higher quality images but take longer to process
- The script is designed to work with the existing project structure
- All operations are logged to the console for monitoring progress
- The alternative method (`--alt`) is recommended for most use cases 