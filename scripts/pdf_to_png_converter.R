#!/usr/bin/env Rscript

# PDF to PNG Converter Script
# This script converts each page of a PDF file to individual PNG images
# Usage: Rscript pdf_to_png_converter.R [input_pdf] [output_dir]

# Load required libraries
suppressPackageStartupMessages({
  if (!require(pdftools, quietly = TRUE)) {
    install.packages("pdftools", repos = "https://cran.rstudio.com/")
    library(pdftools)
  }
  if (!require(magick, quietly = TRUE)) {
    install.packages("magick", repos = "https://cran.rstudio.com/")
    library(magick)
  }
})

# Function to convert PDF to PNG
convert_pdf_to_png <- function(input_pdf, output_dir = NULL, dpi = 300) {
  
  # Check if input file exists
  if (!file.exists(input_pdf)) {
    stop("Input PDF file does not exist: ", input_pdf)
  }
  
  # If no output directory specified, create one based on input filename
  if (is.null(output_dir)) {
    input_basename <- tools::file_path_sans_ext(basename(input_pdf))
    output_dir <- file.path("12-Days-to-Deming", "PNGs")
  }
  
  # Create output directory if it doesn't exist
  if (!dir.exists(output_dir)) {
    dir.create(output_dir, recursive = TRUE)
    cat("Created output directory:", output_dir, "\n")
  }
  
  # Get number of pages in PDF
  pdf_info <- pdf_info(input_pdf)
  num_pages <- pdf_info$pages
  
  cat("Converting PDF:", basename(input_pdf), "\n")
  cat("Number of pages:", num_pages, "\n")
  cat("Output directory:", output_dir, "\n")
  cat("DPI:", dpi, "\n\n")
  
  # Convert each page to PNG
  for (page_num in 1:num_pages) {
    # Create output filename
    input_basename <- tools::file_path_sans_ext(basename(input_pdf))
    output_filename <- paste0(input_basename, "_page_", sprintf("%03d", page_num), ".png")
    output_path <- file.path(output_dir, output_filename)
    
    cat("Converting page", page_num, "of", num_pages, "... ")
    
    tryCatch({
      # Convert single page to image using pdf_render_page
      img <- pdf_render_page(input_pdf, page = page_num, dpi = dpi)
      
      # Convert to magick image if it's not already
      if (!inherits(img, "magick-image")) {
        # If img is a raw vector, convert it to magick image
        if (is.raw(img)) {
          img <- image_read(img)
        } else {
          # Try to convert using image_read
          img <- image_read(img)
        }
      }
      
      # Save as PNG
      image_write(img, output_path, format = "png")
      
      cat("✓ Saved as", output_filename, "\n")
      
    }, error = function(e) {
      cat("✗ Error converting page", page_num, ":", e$message, "\n")
    })
  }
  
  cat("\nConversion complete!\n")
  cat("Output files saved in:", output_dir, "\n")
}

# Function to convert PDF to single PNG (all pages combined)
convert_pdf_to_single_png <- function(input_pdf, output_dir = NULL, dpi = 300) {
  
  # Check if input file exists
  if (!file.exists(input_pdf)) {
    stop("Input PDF file does not exist: ", input_pdf)
  }
  
  # If no output directory specified, create one based on input filename
  if (is.null(output_dir)) {
    output_dir <- file.path("12-Days-to-Deming", "PNGs")
  }
  
  # Create output directory if it doesn't exist
  if (!dir.exists(output_dir)) {
    dir.create(output_dir, recursive = TRUE)
    cat("Created output directory:", output_dir, "\n")
  }
  
  # Create output filename
  input_basename <- tools::file_path_sans_ext(basename(input_pdf))
  output_filename <- paste0(input_basename, ".png")
  output_path <- file.path(output_dir, output_filename)
  
  cat("Converting PDF to single PNG:", basename(input_pdf), "\n")
  cat("Output:", output_filename, "\n")
  cat("DPI:", dpi, "\n\n")
  
  tryCatch({
    # Convert all pages to images
    img <- pdf_render_page(input_pdf, dpi = dpi)
    
    # Convert to magick image if it's not already
    if (!inherits(img, "magick-image")) {
      # If img is a raw vector, convert it to magick image
      if (is.raw(img)) {
        img <- image_read(img)
      } else {
        # Try to convert using image_read
        img <- image_read(img)
      }
    }
    
    # Save as PNG
    image_write(img, output_path, format = "png")
    
    cat("✓ Conversion complete! Saved as", output_filename, "\n")
    
  }, error = function(e) {
    cat("✗ Error converting PDF:", e$message, "\n")
  })
}

# Alternative function using pdf_convert (more reliable)
convert_pdf_to_png_alt <- function(input_pdf, output_dir = NULL, dpi = 300) {
  
  # Check if input file exists
  if (!file.exists(input_pdf)) {
    stop("Input PDF file does not exist: ", input_pdf)
  }
  
  # If no output directory specified, create one based on input filename
  if (is.null(output_dir)) {
    input_basename <- tools::file_path_sans_ext(basename(input_pdf))
    output_dir <- file.path("12-Days-to-Deming", "PNGs")
  }
  
  # Create output directory if it doesn't exist
  if (!dir.exists(output_dir)) {
    dir.create(output_dir, recursive = TRUE)
    cat("Created output directory:", output_dir, "\n")
  }
  
  # Get number of pages in PDF
  pdf_info <- pdf_info(input_pdf)
  num_pages <- pdf_info$pages
  
  cat("Converting PDF:", basename(input_pdf), "\n")
  cat("Number of pages:", num_pages, "\n")
  cat("Output directory:", output_dir, "\n")
  cat("DPI:", dpi, "\n\n")
  
  # Create output filename pattern
  input_basename <- tools::file_path_sans_ext(basename(input_pdf))
  output_pattern <- file.path(output_dir, paste0(input_basename, "_page_%03d.png"))
  
  tryCatch({
    # Convert PDF to PNG files using pdf_convert
    pdf_convert(input_pdf, format = "png", pages = 1:num_pages, 
                filenames = sprintf(output_pattern, 1:num_pages), dpi = dpi)
    
    cat("✓ Conversion complete!\n")
    cat("Output files saved in:", output_dir, "\n")
    
  }, error = function(e) {
    cat("✗ Error converting PDF:", e$message, "\n")
  })
}

# Main execution
main <- function() {
  # Get command line arguments
  args <- commandArgs(trailingOnly = TRUE)
  
  if (length(args) == 0) {
    # Example usage if no arguments provided
    cat("PDF to PNG Converter\n")
    cat("===================\n\n")
    cat("Usage:\n")
    cat("  Rscript pdf_to_png_converter.R <input_pdf> [output_dir] [--single] [--alt]\n\n")
    cat("Examples:\n")
    cat("  Rscript pdf_to_png_converter.R 12-Days-to-Deming/PDFs/E.Day.2.12Oct21.pdf\n")
    cat("  Rscript pdf_to_png_converter.R 12-Days-to-Deming/PDFs/E.Day.2.12Oct21.pdf 12-Days-to-Deming/PNGs\n")
    cat("  Rscript pdf_to_png_converter.R 12-Days-to-Deming/PDFs/E.Day.2.12Oct21.pdf --single\n")
    cat("  Rscript pdf_to_png_converter.R 12-Days-to-Deming/PDFs/E.Day.2.12Oct21.pdf --alt\n\n")
    cat("Options:\n")
    cat("  --single    Convert all pages to a single PNG file\n")
    cat("  --alt       Use alternative conversion method (pdf_convert)\n")
    cat("  --dpi=N     Set DPI (default: 300)\n\n")
    
    # Run example conversion
    example_pdf <- "12-Days-to-Deming/PDFs/E.Day.2.12Oct21.pdf"
    if (file.exists(example_pdf)) {
      cat("Running example conversion...\n")
      convert_pdf_to_png_alt(example_pdf)  # Use alternative method by default
    } else {
      cat("Example PDF not found:", example_pdf, "\n")
    }
    return()
  }
  
  # Parse arguments
  input_pdf <- args[1]
  output_dir <- NULL
  single_file <- FALSE
  use_alt_method <- FALSE
  dpi <- 300
  
  if (length(args) > 1) {
    for (i in 2:length(args)) {
      if (args[i] == "--single") {
        single_file <- TRUE
      } else if (args[i] == "--alt") {
        use_alt_method <- TRUE
      } else if (grepl("^--dpi=", args[i])) {
        dpi <- as.numeric(sub("^--dpi=", "", args[i]))
      } else if (!grepl("^--", args[i])) {
        output_dir <- args[i]
      }
    }
  }
  
  # Perform conversion
  if (single_file) {
    convert_pdf_to_single_png(input_pdf, output_dir, dpi)
  } else if (use_alt_method) {
    convert_pdf_to_png_alt(input_pdf, output_dir, dpi)
  } else {
    convert_pdf_to_png(input_pdf, output_dir, dpi)
  }
}

# Run main function if script is executed directly
if (!interactive()) {
  main()
} 