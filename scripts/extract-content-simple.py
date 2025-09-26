#!/usr/bin/env python3
"""
extract-content-simple.py
Simplified OCR and text extraction from PNG files using Tesseract
Usage: python scripts/extract-content-simple.py --day 3 --pages 001-003 --output temp/day-03-text/
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
from datetime import datetime

# Set up logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

class SimpleContentExtractor:
    """Extract text content from PNG files using OCR"""
    
    def __init__(self, source_dir: str, output_dir: str):
        self.source_dir = Path(source_dir)
        self.output_dir = Path(output_dir)
        self.output_dir.mkdir(parents=True, exist_ok=True)
        
        # Configure Tesseract
        self.tesseract_config = '--oem 3 --psm 6'
    
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
        
        return thresh
    
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
        
        # Extract text using Tesseract
        try:
            raw_text = pytesseract.image_to_string(pil_image, config=self.tesseract_config)
            
            # Process the text
            processed_text = self.process_ocr_text(raw_text)
            
            return {
                "filename": image_path.name,
                "page_number": page_number,
                "raw_text": raw_text,
                "processed_text": processed_text,
                "extraction_timestamp": datetime.now().isoformat()
            }
            
        except Exception as e:
            logger.error(f"OCR failed for {image_path.name}: {str(e)}")
            return {
                "filename": image_path.name,
                "page_number": page_number,
                "error": str(e),
                "extraction_timestamp": datetime.now().isoformat()
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
            
            processed_lines.append({
                "text": line,
                "type": line_type,
                "timing": timing_info,
                "activity": activity_info
            })
        
        return {
            "lines": processed_lines,
            "total_lines": len(processed_lines),
            "headings": [line for line in processed_lines if line["type"] == "heading"],
            "timing_indicators": [line for line in processed_lines if line["timing"]],
            "activity_indicators": [line for line in processed_lines if line["activity"]]
        }
    
    def classify_line(self, line: str) -> str:
        """Classify a line as heading, paragraph, list item, etc."""
        if not line:
            return "empty"
        
        # Check for headings
        if re.match(r'^[A-Z][A-Z\s]{10,}$', line):  # ALL CAPS headings
            return "heading"
        if re.match(r'^\d+\.\s+[A-Z]', line):       # Numbered headings
            return "heading"
        if re.match(r'^[A-Z][a-z]+\s+[A-Z]', line): # Title case headings
            return "heading"
        if re.match(r'^Day\s+\d+', line):           # Day headings
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
        timing_patterns = [
            r'\d+\s*minutes?',
            r'\d+\s*hours?',
            r'timing:\s*\d+',
            r'duration:\s*\d+',
            r'allow\s+\d+',
            r'spend\s+\d+',
            r'take\s+\d+'
        ]
        
        for pattern in timing_patterns:
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
        activity_patterns = [
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
        
        for pattern in activity_patterns:
            match = re.search(pattern, line, re.IGNORECASE)
            if match:
                return {
                    "pattern": pattern,
                    "match": match.group(0),
                    "position": match.start()
                }
        return None
    
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
            "extraction_timestamp": datetime.now().isoformat(),
            "pages": []
        }
        
        for png_file in png_files:
            page_content = self.extract_text_from_image(png_file)
            if page_content:
                results["pages"].append(page_content)
        
        # Save results as text files instead of JSON
        self.save_text_results(results)
        
        logger.info(f"Day {day} content extraction complete: {len(results['pages'])} pages processed")
        
        return results
    
    def save_text_results(self, results: Dict):
        """Save results as text files"""
        day = results["day"]
        
        # Save raw text
        raw_text_file = self.output_dir / f"day-{day}-raw-text.txt"
        with open(raw_text_file, 'w', encoding='utf-8') as f:
            f.write(f"Day {day} Raw Text Extraction\n")
            f.write("=" * 50 + "\n\n")
            
            for page in results["pages"]:
                f.write(f"Page {page['page_number']}: {page['filename']}\n")
                f.write("-" * 30 + "\n")
                if "raw_text" in page:
                    f.write(page["raw_text"])
                f.write("\n\n")
        
        # Save processed text
        processed_text_file = self.output_dir / f"day-{day}-processed-text.txt"
        with open(processed_text_file, 'w', encoding='utf-8') as f:
            f.write(f"Day {day} Processed Text Extraction\n")
            f.write("=" * 50 + "\n\n")
            
            for page in results["pages"]:
                f.write(f"Page {page['page_number']}: {page['filename']}\n")
                f.write("-" * 30 + "\n")
                
                if "processed_text" in page:
                    processed = page["processed_text"]
                    f.write(f"Total lines: {processed['total_lines']}\n")
                    f.write(f"Headings: {len(processed['headings'])}\n")
                    f.write(f"Timing indicators: {len(processed['timing_indicators'])}\n")
                    f.write(f"Activity indicators: {len(processed['activity_indicators'])}\n\n")
                    
                    # Write all lines
                    for line in processed["lines"]:
                        f.write(f"[{line['type']}] {line['text']}\n")
                        if line['timing']:
                            f.write(f"  -> Timing: {line['timing']['match']}\n")
                        if line['activity']:
                            f.write(f"  -> Activity: {line['activity']['match']}\n")
                    f.write("\n")
        
        # Save summary
        summary_file = self.output_dir / f"day-{day}-summary.txt"
        with open(summary_file, 'w', encoding='utf-8') as f:
            f.write(f"Day {day} Content Summary\n")
            f.write("=" * 50 + "\n\n")
            f.write(f"Total pages processed: {results['total_pages']}\n")
            f.write(f"Page range: {results['page_range']}\n")
            f.write(f"Extraction timestamp: {results['extraction_timestamp']}\n\n")
            
            total_headings = 0
            total_timing = 0
            total_activities = 0
            
            for page in results["pages"]:
                if "processed_text" in page:
                    processed = page["processed_text"]
                    total_headings += len(processed['headings'])
                    total_timing += len(processed['timing_indicators'])
                    total_activities += len(processed['activity_indicators'])
            
            f.write(f"Total headings found: {total_headings}\n")
            f.write(f"Total timing indicators: {total_timing}\n")
            f.write(f"Total activity indicators: {total_activities}\n")

def main():
    parser = argparse.ArgumentParser(description="Extract text content from PNG files using OCR")
    parser.add_argument("--day", type=int, required=True, help="Day number to process")
    parser.add_argument("--pages", help="Page range to process (e.g., '005-020')")
    parser.add_argument("--source-dir", default="12-Days-to-Deming/PNGs/", help="Source directory for PNG files")
    parser.add_argument("--output", default="temp/day-03-text/", help="Output directory for extracted content")
    
    args = parser.parse_args()
    
    # Update output directory to include day number
    output_dir = args.output.replace("day-03", f"day-{args.day:02d}")
    
    extractor = SimpleContentExtractor(args.source_dir, output_dir)
    results = extractor.extract_day_content(args.day, args.pages)
    
    if results:
        print(f"Content extraction complete for Day {args.day}")
        print(f"Results saved to: {output_dir}")
        print(f"Files created:")
        print(f"  - day-{args.day}-raw-text.txt")
        print(f"  - day-{args.day}-processed-text.txt")
        print(f"  - day-{args.day}-summary.txt")
    else:
        print(f"No content extracted for Day {args.day}")

if __name__ == "__main__":
    main()
