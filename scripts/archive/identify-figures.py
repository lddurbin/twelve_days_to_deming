#!/usr/bin/env python3
"""
identify-figures.py
Detect charts, tables, images to extract from PNG files
Usage: python scripts/identify-figures.py --day 3 --source-dir 12-Days-to-Deming/PNGs/ --output temp/analysis
"""

import argparse
import os
import json
import cv2
import numpy as np
import pandas as pd
from pathlib import Path
import re
from typing import List, Dict, Tuple, Optional
import logging

# Set up logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

class FigureDetector:
    """Detect and analyze figures in PNG images"""
    
    def __init__(self, source_dir: str, output_dir: str):
        self.source_dir = Path(source_dir)
        self.output_dir = Path(output_dir)
        self.output_dir.mkdir(parents=True, exist_ok=True)
        
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
        """Parse page range string like '005-020' or '010'"""
        if '-' in page_range:
            start, end = page_range.split('-')
            return int(start), int(end)
        else:
            page_num = int(page_range)
            return page_num, page_num
    
    def detect_rectangles(self, image: np.ndarray) -> List[Tuple[int, int, int, int]]:
        """Detect rectangular regions that might be figures"""
        gray = cv2.cvtColor(image, cv2.COLOR_BGR2GRAY)
        
        # Apply edge detection
        edges = cv2.Canny(gray, 50, 150, apertureSize=3)
        
        # Find contours
        contours, _ = cv2.findContours(edges, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
        
        rectangles = []
        for contour in contours:
            # Approximate contour to polygon
            epsilon = 0.02 * cv2.arcLength(contour, True)
            approx = cv2.approxPolyDP(contour, epsilon, True)
            
            # Check if it's roughly rectangular
            if len(approx) >= 4:
                x, y, w, h = cv2.boundingRect(contour)
                area = w * h
                
                # Filter by size (avoid tiny rectangles)
                if area > 10000:  # Minimum area threshold
                    rectangles.append((x, y, w, h))
        
        return rectangles
    
    def detect_text_regions(self, image: np.ndarray) -> List[Tuple[int, int, int, int]]:
        """Detect regions with dense text (potential tables)"""
        gray = cv2.cvtColor(image, cv2.COLOR_BGR2GRAY)
        
        # Apply morphological operations to detect text regions
        kernel = cv2.getStructuringElement(cv2.MORPH_RECT, (9, 1))
        dilated = cv2.dilate(gray, kernel, iterations=1)
        
        # Find contours of text regions
        contours, _ = cv2.findContours(dilated, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
        
        text_regions = []
        for contour in contours:
            x, y, w, h = cv2.boundingRect(contour)
            area = w * h
            
            # Filter by size and aspect ratio (tables are usually wider than tall)
            if area > 5000 and w > h * 1.5:
                text_regions.append((x, y, w, h))
        
        return text_regions
    
    def detect_charts(self, image: np.ndarray) -> List[Tuple[int, int, int, int]]:
        """Detect chart-like regions (areas with lines, curves, or colored regions)"""
        gray = cv2.cvtColor(image, cv2.COLOR_BGR2GRAY)
        
        # Detect lines using Hough transform
        lines = cv2.HoughLinesP(gray, 1, np.pi/180, threshold=100, minLineLength=50, maxLineGap=10)
        
        if lines is not None and len(lines) > 10:  # Charts typically have many lines
            # Find bounding box of all lines
            all_points = []
            for line in lines:
                x1, y1, x2, y2 = line[0]
                all_points.extend([(x1, y1), (x2, y2)])
            
            if all_points:
                points = np.array(all_points)
                x, y, w, h = cv2.boundingRect(points)
                return [(x, y, w, h)]
        
        return []
    
    def analyze_image(self, image_path: Path) -> Dict:
        """Analyze a single image for figures"""
        logger.info(f"Analyzing {image_path.name}")
        
        # Load image
        image = cv2.imread(str(image_path))
        if image is None:
            logger.error(f"Could not load image: {image_path}")
            return {}
        
        height, width = image.shape[:2]
        
        # Extract page number from filename
        page_match = re.search(r'page_(\d+)', image_path.name)
        page_number = int(page_match.group(1)) if page_match else 0
        
        # Detect different types of figures
        rectangles = self.detect_rectangles(image)
        text_regions = self.detect_text_regions(image)
        charts = self.detect_charts(image)
        
        # Combine and deduplicate regions
        all_regions = rectangles + text_regions + charts
        unique_regions = self.deduplicate_regions(all_regions)
        
        return {
            "filename": image_path.name,
            "page_number": page_number,
            "dimensions": {"width": width, "height": height},
            "figures": {
                "rectangles": len(rectangles),
                "text_regions": len(text_regions),
                "charts": len(charts),
                "total_unique": len(unique_regions)
            },
            "regions": [
                {
                    "type": self.classify_region((x, y, w, h), image),
                    "bbox": {"x": x, "y": y, "width": w, "height": h},
                    "area": w * h,
                    "center": {"x": x + w//2, "y": y + h//2}
                }
                for x, y, w, h in unique_regions
            ]
        }
    
    def deduplicate_regions(self, regions: List[Tuple[int, int, int, int]], 
                          overlap_threshold: float = 0.5) -> List[Tuple[int, int, int, int]]:
        """Remove overlapping regions"""
        if not regions:
            return []
        
        # Sort by area (largest first)
        regions_with_area = [(r, r[2] * r[3]) for r in regions]
        regions_with_area.sort(key=lambda x: x[1], reverse=True)
        
        unique_regions = []
        for region, _ in regions_with_area:
            x1, y1, w1, h1 = region
            
            # Check overlap with existing regions
            overlaps = False
            for existing in unique_regions:
                x2, y2, w2, h2 = existing
                
                # Calculate intersection
                x_left = max(x1, x2)
                y_top = max(y1, y2)
                x_right = min(x1 + w1, x2 + w2)
                y_bottom = min(y1 + h1, y2 + h2)
                
                if x_right > x_left and y_bottom > y_top:
                    intersection_area = (x_right - x_left) * (y_bottom - y_top)
                    union_area = w1 * h1 + w2 * h2 - intersection_area
                    overlap_ratio = intersection_area / union_area if union_area > 0 else 0
                    
                    if overlap_ratio > overlap_threshold:
                        overlaps = True
                        break
            
            if not overlaps:
                unique_regions.append(region)
        
        return unique_regions
    
    def classify_region(self, region: Tuple[int, int, int, int], image: np.ndarray) -> str:
        """Classify a region as chart, table, or figure"""
        x, y, w, h = region
        
        # Extract region
        roi = image[y:y+h, x:x+w]
        if roi.size == 0:
            return "unknown"
        
        # Convert to grayscale
        gray_roi = cv2.cvtColor(roi, cv2.COLOR_BGR2GRAY)
        
        # Detect edges
        edges = cv2.Canny(gray_roi, 50, 150)
        edge_density = np.sum(edges > 0) / (w * h)
        
        # Detect lines
        lines = cv2.HoughLinesP(edges, 1, np.pi/180, threshold=30, minLineLength=20, maxLineGap=5)
        line_count = len(lines) if lines is not None else 0
        
        # Classify based on characteristics
        if line_count > 20:
            return "chart"
        elif edge_density > 0.1:
            return "figure"
        else:
            return "table"
    
    def analyze_day(self, day: int, page_range: Optional[str] = None) -> Dict:
        """Analyze PNG files for a specific day, optionally filtered by page range"""
        png_files = self.find_day_pngs(day, page_range)
        
        if not png_files:
            logger.error(f"No PNG files found for Day {day}")
            return {}
        
        logger.info(f"Found {len(png_files)} PNG files for Day {day}")
        
        results = {
            "day": day,
            "total_pages": len(png_files),
            "analysis_timestamp": str(pd.Timestamp.now()),
            "pages": []
        }
        
        for png_file in png_files:
            page_analysis = self.analyze_image(png_file)
            if page_analysis:
                results["pages"].append(page_analysis)
        
        # Save results with chunk identifier if page range specified
        if page_range:
            start_page, end_page = self.parse_page_range(page_range)
            output_file = self.output_dir / f"day-{day}-figures-chunk-{start_page:03d}-{end_page:03d}.json"
        else:
            output_file = self.output_dir / f"day-{day}-figures.json"
        
        with open(output_file, 'w') as f:
            json.dump(results, f, indent=2)
        
        # Create summary
        total_figures = sum(page["figures"]["total_unique"] for page in results["pages"])
        logger.info(f"Day {day} analysis complete: {total_figures} figures detected across {len(results['pages'])} pages")
        
        return results

def main():
    parser = argparse.ArgumentParser(description="Identify figures in PNG files")
    parser.add_argument("--day", type=int, required=True, help="Day number to analyze")
    parser.add_argument("--source-dir", default="12-Days-to-Deming/PNGs/", help="Source directory for PNG files")
    parser.add_argument("--output", default="temp/analysis", help="Output directory for analysis results")
    parser.add_argument("--pages", help="Page range to process (e.g., '005-020')")
    
    args = parser.parse_args()
    
    detector = FigureDetector(args.source_dir, args.output)
    results = detector.analyze_day(args.day, page_range=args.pages)
    
    if results:
        print(f"Analysis complete for Day {args.day}")
        print(f"Results saved to: {args.output}/day-{args.day}-figures.json")
    else:
        print(f"No results generated for Day {args.day}")

if __name__ == "__main__":
    main()
