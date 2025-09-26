#!/usr/bin/env python3
"""
extract-content.py
OCR and text extraction from PNG files using Tesseract
Usage: python scripts/extract-content.py --day 3 --pages 005-020 --output temp/day-03-text/
"""

import argparse
import os
import json
import cv2
import numpy as np
from pathlib import Path
import re
from typing import List, Dict, Tuple, Optional
import logging
import pytesseract
from PIL import Image
import pandas as pd

# Set up logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

class ContentExtractor:
    """Extract text content from PNG files using OCR"""
    
    def __init__(self, source_dir: str, output_dir: str):
        self.source_dir = Path(source_dir)
        self.output_dir = Path(output_dir)
        self.output_dir.mkdir(parents=True, exist_ok=True)
        
        # Configure Tesseract
        self.tesseract_config = '--oem 3 --psm 6'
        
        # Patterns for different content types
        self.heading_patterns = [
            r'^[A-Z][A-Z\s]{10,}$',  # ALL CAPS headings
            r'^\d+\.\s+[A-Z]',       # Numbered headings
            r'^[A-Z][a-z]+\s+[A-Z]', # Title case headings
            r'^Day\s+\d+',           # Day headings
            r'^Chapter\s+\d+',       # Chapter headings
        ]
        
        self.timing_patterns = [
            r'\d+\s*minutes?',
            r'\d+\s*hours?',
            r'timing:\s*\d+',
            r'duration:\s*\d+',
            r'allow\s+\d+',
            r'spend\s+\d+',
            r'take\s+\d+',
            r'⏰\s*\d+',
            r'🕐\s*\d+',
            r'⏱️\s*\d+'
        ]
        
        self.activity_patterns = [
            r'pause\s+for\s+thought',
            r'activity\s+\d+',
            r'exercise\s+\d+',
            r'think\s+about',
            r'reflect\s+on',
            r'discuss\s+with',
            r'work\s+in\s+groups',
            r'individual\s+work',
            r'group\s+discussion',
            r'break\s+out\s+session',
            r'workshop',
            r'hands-on',
            r'practical\s+exercise'
        ]
        
        self.equation_patterns = [
            r'[a-zA-Z]\s*[+\-*/=]\s*[a-zA-Z0-9]',
            r'\d+\s*[+\-*/=]\s*\d+',
            r'[a-zA-Z]\s*=\s*[a-zA-Z0-9]',
            r'[a-zA-Z]\s*\(\s*[a-zA-Z0-9]',
            r'[a-zA-Z]\s*\)\s*[a-zA-Z0-9]'
        ]
    
    def find_day_pngs(self, day: int, page_range: Optional[str] = None) -> List[Path]:
        """Find PNG files for a specific day, optionally filtered by page range"""
        pattern = f"*Day.{day}*"
        png_files = list(self.source_dir.glob(pattern))
        png_files = sorted(png_files)
        
        if page_range:
            start_page, end_page = self.parse_page_range(page_range)
            filtered_files = []
            for file in png_files:
                page_match = re.search(r'page_(\d+)', file.name)
                if page_match:
                    page_num = int(page_match.group(1))
                    if start_page <= page_num <= end_page:
                        filtered_files.append(file)
            return filtered_files
        
        return png_files
    
    def parse_page_range(self, page_range: str) -> Tuple[int, int]:
        """Parse page range string like '005-020' into start and end page numbers"""
        if '-' in page_range:
            start, end = page_range.split('-')
            return int(start), int(end)
        else:
            page_num = int(page_range)
            return page_num, page_num
    
    def preprocess_image(self, image: np.ndarray) -> np.ndarray:
        """Preprocess image for better OCR results"""
        # Convert to grayscale
        gray = cv2.cvtColor(image, cv2.COLOR_BGR2GRAY)
        
        # Apply denoising
        denoised = cv2.fastNlMeansDenoising(gray)
        
        # Apply adaptive thresholding
        thresh = cv2.adaptiveThreshold(denoised, 255, cv2.ADAPTIVE_THRESH_GAUSSIAN_C, cv2.THRESH_BINARY, 11, 2)
        
        # Apply morphological operations to clean up
        kernel = np.ones((1, 1), np.uint8)
        cleaned = cv2.morphologyEx(thresh, cv2.MORPH_CLOSE, kernel)
        
        return cleaned
    
    def detect_text_regions(self, image: np.ndarray) -> List[Tuple[int, int, int, int]]:
        """Detect text regions in the image for better OCR"""
        gray = cv2.cvtColor(image, cv2.COLOR_BGR2GRAY)
        
        # Apply edge detection
        edges = cv2.Canny(gray, 50, 150, apertureSize=3)
        
        # Find contours
        contours, _ = cv2.findContours(edges, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
        
        text_regions = []
        for contour in contours:
            x, y, w, h = cv2.boundingRect(contour)
            area = w * h
            
            # Filter by size and aspect ratio
            if area > 1000 and w > 50 and h > 20:
                text_regions.append((x, y, w, h))
        
        return text_regions
    
    def detect_columns(self, image: np.ndarray) -> List[Tuple[int, int, int, int]]:
        """Detect column boundaries in multi-column layouts"""
        gray = cv2.cvtColor(image, cv2.COLOR_BGR2GRAY)
        height, width = gray.shape
        
        # Project the image vertically to find column boundaries
        vertical_projection = np.sum(gray, axis=0)
        
        # Find valleys (low values) in the projection which indicate column separators
        # Smooth the projection to reduce noise
        from scipy import ndimage
        smoothed = ndimage.gaussian_filter1d(vertical_projection, sigma=10)
        
        # Find local minima
        from scipy.signal import find_peaks
        valleys, _ = find_peaks(-smoothed, distance=width//10, prominence=np.std(smoothed))
        
        # Create column regions
        columns = []
        prev_x = 0
        for valley in valleys:
            if valley - prev_x > width//4:  # Minimum column width
                columns.append((prev_x, 0, valley - prev_x, height))
                prev_x = valley
        
        # Add the last column
        if width - prev_x > width//4:
            columns.append((prev_x, 0, width - prev_x, height))
        
        return columns
    
    def extract_text_from_columns(self, image: np.ndarray, columns: List[Tuple[int, int, int, int]]) -> List[str]:
        """Extract text from each column separately"""
        column_texts = []
        
        for x, y, w, h in columns:
            # Extract column region
            column_region = image[y:y+h, x:x+w]
            
            # Preprocess column
            processed_column = self.preprocess_image(column_region)
            
            # Convert to PIL Image for Tesseract
            pil_image = Image.fromarray(processed_column)
            
            # Extract text from column
            try:
                column_text = pytesseract.image_to_string(pil_image, config=self.tesseract_config)
                column_texts.append(column_text.strip())
            except Exception as e:
                logger.warning(f"Failed to extract text from column: {str(e)}")
                column_texts.append("")
        
        return column_texts
    
    def merge_column_text(self, column_texts: List[str]) -> str:
        """Merge text from multiple columns into a single text stream"""
        if not column_texts:
            return ""
        
        if len(column_texts) == 1:
            return column_texts[0]
        
        # Split each column into lines
        column_lines = [text.split('\n') for text in column_texts]
        
        # Find the maximum number of lines
        max_lines = max(len(lines) for lines in column_lines)
        
        # Merge lines from all columns
        merged_lines = []
        for i in range(max_lines):
            line_parts = []
            for lines in column_lines:
                if i < len(lines) and lines[i].strip():
                    line_parts.append(lines[i].strip())
            
            if line_parts:
                merged_lines.append(' '.join(line_parts))
        
        return '\n'.join(merged_lines)
    
    def extract_text_from_image(self, image_path: Path) -> Dict:
        """Extract text from a single image using OCR"""
        logger.info(f"Processing {image_path.name}")
        
        # Load image
        image = cv2.imread(str(image_path))
        if image is None:
            logger.error(f"Could not load image: {image_path}")
            return {}
        
        # Extract page number from filename
        page_match = re.search(r'page_(\d+)', image_path.name)
        page_number = int(page_match.group(1)) if page_match else 0
        
        # Preprocess image
        processed_image = self.preprocess_image(image)
        
        # Convert to PIL Image for Tesseract
        pil_image = Image.fromarray(processed_image)
        
        # Detect columns for multi-column layout
        columns = self.detect_columns(image)
        
        # Extract text using Tesseract
        try:
            if len(columns) > 1:
                # Multi-column layout - extract from each column separately
                column_texts = self.extract_text_from_columns(image, columns)
                raw_text = self.merge_column_text(column_texts)
            else:
                # Single column layout
                raw_text = pytesseract.image_to_string(pil_image, config=self.tesseract_config)
            
            # Get detailed OCR data
            ocr_data = pytesseract.image_to_data(pil_image, output_type=pytesseract.Output.DICT)
            
            # Process the text
            processed_text = self.process_ocr_text(raw_text)
            
            return {
                "filename": image_path.name,
                "page_number": page_number,
                "raw_text": raw_text,
                "processed_text": processed_text,
                "ocr_data": ocr_data,
                "text_regions": self.detect_text_regions(image),
                "columns": columns,
                "column_count": len(columns),
                "extraction_timestamp": str(pd.Timestamp.now())
            }
            
        except Exception as e:
            logger.error(f"OCR failed for {image_path.name}: {str(e)}")
            return {
                "filename": image_path.name,
                "page_number": page_number,
                "error": str(e),
                "extraction_timestamp": str(pd.Timestamp.now())
            }
    
    def process_ocr_text(self, raw_text: str) -> Dict:
        """Process OCR text to extract structured content"""
        lines = raw_text.split('\n')
        processed_lines = []
        
        for line in lines:
            line = line.strip()
            if not line:
                continue
            
            # Classify line type
            line_type = self.classify_line(line)
            
            # Extract timing information
            timing_info = self.extract_timing_info(line)
            
            # Extract activity information
            activity_info = self.extract_activity_info(line)
            
            # Extract equations
            equations = self.extract_equations(line)
            
            processed_lines.append({
                "text": line,
                "type": line_type,
                "timing": timing_info,
                "activity": activity_info,
                "equations": equations
            })
        
        return {
            "lines": processed_lines,
            "total_lines": len(processed_lines),
            "headings": [line for line in processed_lines if line["type"] == "heading"],
            "timing_indicators": [line for line in processed_lines if line["timing"]],
            "activity_indicators": [line for line in processed_lines if line["activity"]],
            "equations": [line for line in processed_lines if line["equations"]]
        }
    
    def classify_line(self, line: str) -> str:
        """Classify a line as heading, paragraph, list item, etc."""
        if not line:
            return "empty"
        
        # Check for headings
        for pattern in self.heading_patterns:
            if re.match(pattern, line, re.IGNORECASE):
                return "heading"
        
        # Check for list items
        if re.match(r'^\d+\.\s+', line) or re.match(r'^[•\-\*]\s+', line):
            return "list_item"
        
        # Check for short lines (might be headings)
        if len(line) < 50 and line.isupper():
            return "heading"
        
        # Default to paragraph
        return "paragraph"
    
    def extract_timing_info(self, line: str) -> Optional[Dict]:
        """Extract timing information from a line"""
        for pattern in self.timing_patterns:
            match = re.search(pattern, line, re.IGNORECASE)
            if match:
                return {
                    "pattern": pattern,
                    "match": match.group(0),
                    "position": match.start()
                }
        return None
    
    def extract_activity_info(self, line: str) -> Optional[Dict]:
        """Extract activity information from a line"""
        for pattern in self.activity_patterns:
            match = re.search(pattern, line, re.IGNORECASE)
            if match:
                return {
                    "pattern": pattern,
                    "match": match.group(0),
                    "position": match.start()
                }
        return None
    
    def extract_equations(self, line: str) -> List[Dict]:
        """Extract mathematical equations from a line"""
        equations = []
        for pattern in self.equation_patterns:
            matches = re.finditer(pattern, line)
            for match in matches:
                equations.append({
                    "pattern": pattern,
                    "match": match.group(0),
                    "position": match.start()
                })
        return equations
    
    def extract_day_content(self, day: int, page_range: Optional[str] = None) -> Dict:
        """Extract content from all PNG files for a specific day"""
        png_files = self.find_day_pngs(day, page_range)
        
        if not png_files:
            logger.error(f"No PNG files found for Day {day}")
            return {}
        
        logger.info(f"Found {len(png_files)} PNG files for Day {day}")
        
        results = {
            "day": day,
            "page_range": page_range,
            "total_pages": len(png_files),
            "extraction_timestamp": str(pd.Timestamp.now()),
            "pages": []
        }
        
        for png_file in png_files:
            page_content = self.extract_text_from_image(png_file)
            if page_content:
                results["pages"].append(page_content)
        
        # Save results
        output_file = self.output_dir / f"day-{day}-content.json"
        with open(output_file, 'w', encoding='utf-8') as f:
            # Convert numpy types to Python types for JSON serialization
            def convert_numpy(obj):
                if isinstance(obj, (np.integer, np.int64, np.int32)):
                    return int(obj)
                elif isinstance(obj, (np.floating, np.float64, np.float32)):
                    return float(obj)
                elif isinstance(obj, np.ndarray):
                    return obj.tolist()
                elif hasattr(obj, 'item'):  # Handle other numpy scalars
                    return obj.item()
                return obj
            
            # Recursively convert numpy types
            def clean_dict(d):
                if isinstance(d, dict):
                    return {k: clean_dict(v) for k, v in d.items()}
                elif isinstance(d, list):
                    return [clean_dict(item) for item in d]
                else:
                    return convert_numpy(d)
            
            cleaned_results = clean_dict(results)
            json.dump(cleaned_results, f, indent=2, ensure_ascii=False)
        
        # Create text summary
        self.create_text_summary(results)
        
        # Create CSV export
        self.create_csv_export(results)
        
        logger.info(f"Day {day} content extraction complete: {len(results['pages'])} pages processed")
        
        return results
    
    def create_text_summary(self, results: Dict):
        """Create a human-readable text summary"""
        day = results["day"]
        output_file = self.output_dir / f"day-{day}-text-summary.txt"
        
        with open(output_file, 'w', encoding='utf-8') as f:
            f.write(f"Day {day} Content Summary\n")
            f.write("=" * 50 + "\n\n")
            
            for page in results["pages"]:
                f.write(f"Page {page['page_number']}: {page['filename']}\n")
                f.write("-" * 30 + "\n")
                
                if "processed_text" in page:
                    processed = page["processed_text"]
                    f.write(f"Total lines: {processed['total_lines']}\n")
                    f.write(f"Headings: {len(processed['headings'])}\n")
                    f.write(f"Timing indicators: {len(processed['timing_indicators'])}\n")
                    f.write(f"Activity indicators: {len(processed['activity_indicators'])}\n")
                    f.write(f"Equations: {len(processed['equations'])}\n\n")
                    
                    # Write headings
                    if processed['headings']:
                        f.write("Headings:\n")
                        for heading in processed['headings']:
                            f.write(f"  - {heading['text']}\n")
                        f.write("\n")
                    
                    # Write timing indicators
                    if processed['timing_indicators']:
                        f.write("Timing Indicators:\n")
                        for timing in processed['timing_indicators']:
                            f.write(f"  - {timing['text']}\n")
                        f.write("\n")
                    
                    # Write activity indicators
                    if processed['activity_indicators']:
                        f.write("Activity Indicators:\n")
                        for activity in processed['activity_indicators']:
                            f.write(f"  - {activity['text']}\n")
                        f.write("\n")
                
                f.write("\n")
    
    def create_csv_export(self, results: Dict):
        """Create CSV export of extracted content"""
        day = results["day"]
        output_file = self.output_dir / f"day-{day}-content.csv"
        
        rows = []
        for page in results["pages"]:
            if "processed_text" in page:
                for line in page["processed_text"]["lines"]:
                    rows.append({
                        "page_number": page["page_number"],
                        "filename": page["filename"],
                        "line_text": line["text"],
                        "line_type": line["type"],
                        "has_timing": bool(line["timing"]),
                        "has_activity": bool(line["activity"]),
                        "has_equations": bool(line["equations"])
                    })
        
        if rows:
            df = pd.DataFrame(rows)
            df.to_csv(output_file, index=False)

def main():
    parser = argparse.ArgumentParser(description="Extract text content from PNG files using OCR")
    parser.add_argument("--day", type=int, required=True, help="Day number to process")
    parser.add_argument("--pages", help="Page range to process (e.g., '005-020')")
    parser.add_argument("--source-dir", default="12-Days-to-Deming/PNGs/", help="Source directory for PNG files")
    parser.add_argument("--output", default="temp/day-03-text/", help="Output directory for extracted content")
    
    args = parser.parse_args()
    
    # Update output directory to include day number
    output_dir = args.output.replace("day-03", f"day-{args.day:02d}")
    
    extractor = ContentExtractor(args.source_dir, output_dir)
    results = extractor.extract_day_content(args.day, args.pages)
    
    if results:
        print(f"Content extraction complete for Day {args.day}")
        print(f"Results saved to: {output_dir}")
        print(f"Files created:")
        print(f"  - day-{args.day}-content.json")
        print(f"  - day-{args.day}-text-summary.txt")
        print(f"  - day-{args.day}-content.csv")
    else:
        print(f"No content extracted for Day {args.day}")

if __name__ == "__main__":
    main()
