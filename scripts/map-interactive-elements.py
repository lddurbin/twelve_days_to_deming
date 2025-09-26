#!/usr/bin/env python3
"""
map-interactive-elements.py
Identify activities, exercises, and interactive elements in PNG files
Usage: python scripts/map-interactive-elements.py --day 3 --source-dir 12-Days-to-Deming/PNGs/ --output temp/analysis
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

# Set up logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

class InteractiveElementDetector:
    """Detect and map interactive elements in PNG images"""
    
    def __init__(self, source_dir: str, output_dir: str):
        self.source_dir = Path(source_dir)
        self.output_dir = Path(output_dir)
        self.output_dir.mkdir(parents=True, exist_ok=True)
        
        # Common patterns for interactive elements
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
        
        self.timing_patterns = [
            r'\d+\s*minutes?',
            r'\d+\s*hours?',
            r'timing:\s*\d+',
            r'duration:\s*\d+',
            r'allow\s+\d+',
            r'spend\s+\d+',
            r'take\s+\d+'
        ]
        
        self.download_patterns = [
            r'download',
            r'handout',
            r'worksheet',
            r'template',
            r'resource',
            r'material',
            r'guide',
            r'checklist'
        ]
        
        self.clock_patterns = [
            r'⏰',
            r'🕐',
            r'🕑',
            r'🕒',
            r'🕓',
            r'🕔',
            r'🕕',
            r'🕖',
            r'🕗',
            r'🕘',
            r'🕙',
            r'🕚',
            r'🕛',
            r'⏱️',
            r'⏲️',
            r'⏳',
            r'⏰',
            r'⏰',
            r'⏰'
        ]
    
    def find_day_pngs(self, day: int) -> List[Path]:
        """Find all PNG files for a specific day"""
        pattern = f"*Day.{day}*"
        png_files = list(self.source_dir.glob(pattern))
        return sorted(png_files)
    
    def detect_text_regions(self, image: np.ndarray) -> List[Tuple[int, int, int, int]]:
        """Detect text regions in the image"""
        gray = cv2.cvtColor(image, cv2.COLOR_BGR2GRAY)
        
        # Apply threshold to get binary image
        _, binary = cv2.threshold(gray, 0, 255, cv2.THRESH_BINARY + cv2.THRESH_OTSU)
        
        # Find contours
        contours, _ = cv2.findContours(binary, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
        
        text_regions = []
        for contour in contours:
            x, y, w, h = cv2.boundingRect(contour)
            area = w * h
            
            # Filter by size (avoid tiny regions)
            if area > 1000 and w > 50 and h > 20:
                text_regions.append((x, y, w, h))
        
        return text_regions
    
    def detect_highlighted_regions(self, image: np.ndarray) -> List[Tuple[int, int, int, int]]:
        """Detect highlighted or colored regions that might indicate interactive elements"""
        # Convert to HSV for better color detection
        hsv = cv2.cvtColor(image, cv2.COLOR_BGR2HSV)
        
        # Define color ranges for highlights (yellow, green, blue, etc.)
        color_ranges = [
            # Yellow highlights
            (np.array([20, 100, 100]), np.array([30, 255, 255])),
            # Green highlights
            (np.array([40, 100, 100]), np.array([80, 255, 255])),
            # Blue highlights
            (np.array([100, 100, 100]), np.array([130, 255, 255])),
            # Red highlights
            (np.array([0, 100, 100]), np.array([10, 255, 255])),
        ]
        
        highlighted_regions = []
        for lower, upper in color_ranges:
            mask = cv2.inRange(hsv, lower, upper)
            contours, _ = cv2.findContours(mask, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
            
            for contour in contours:
                x, y, w, h = cv2.boundingRect(contour)
                area = w * h
                
                if area > 5000:  # Minimum area for highlighted regions
                    highlighted_regions.append((x, y, w, h))
        
        return highlighted_regions
    
    def detect_boxes_and_borders(self, image: np.ndarray) -> List[Tuple[int, int, int, int]]:
        """Detect boxes, borders, or frames that might contain interactive content"""
        gray = cv2.cvtColor(image, cv2.COLOR_BGR2GRAY)
        
        # Apply edge detection
        edges = cv2.Canny(gray, 50, 150, apertureSize=3)
        
        # Find contours
        contours, _ = cv2.findContours(edges, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
        
        boxes = []
        for contour in contours:
            # Approximate contour to polygon
            epsilon = 0.02 * cv2.arcLength(contour, True)
            approx = cv2.approxPolyDP(contour, epsilon, True)
            
            # Check if it's roughly rectangular
            if len(approx) >= 4:
                x, y, w, h = cv2.boundingRect(contour)
                area = w * h
                
                # Filter by size and aspect ratio
                if area > 10000 and w > 100 and h > 50:
                    boxes.append((x, y, w, h))
        
        return boxes
    
    def detect_icons_and_symbols(self, image: np.ndarray) -> List[Tuple[int, int, int, int]]:
        """Detect icons, symbols, or special characters that might indicate interactive elements"""
        gray = cv2.cvtColor(image, cv2.COLOR_BGR2GRAY)
        
        # Apply template matching for common icons
        # This is a simplified approach - in practice, you'd use more sophisticated methods
        
        # Detect circular regions (potential icons)
        circles = cv2.HoughCircles(gray, cv2.HOUGH_GRADIENT, 1, 20, param1=50, param2=30, minRadius=10, maxRadius=50)
        
        icon_regions = []
        if circles is not None:
            circles = np.round(circles[0, :]).astype("int")
            for (x, y, r) in circles:
                icon_regions.append((x-r, y-r, 2*r, 2*r))
        
        return icon_regions
    
    def classify_interactive_element(self, region: Tuple[int, int, int, int], image: np.ndarray) -> Dict:
        """Classify a region as a specific type of interactive element"""
        x, y, w, h = region
        
        # Extract region
        roi = image[y:y+h, x:x+w]
        if roi.size == 0:
            return {"type": "unknown", "confidence": 0.0}
        
        # Convert to grayscale for analysis
        gray_roi = cv2.cvtColor(roi, cv2.COLOR_BGR2GRAY)
        
        # Analyze region characteristics
        area = w * h
        aspect_ratio = w / h if h > 0 else 0
        
        # Detect edges
        edges = cv2.Canny(gray_roi, 50, 150)
        edge_density = np.sum(edges > 0) / (w * h)
        
        # Detect lines
        lines = cv2.HoughLinesP(edges, 1, np.pi/180, threshold=30, minLineLength=20, maxLineGap=5)
        line_count = len(lines) if lines is not None else 0
        
        # Classify based on characteristics
        if edge_density > 0.15 and line_count > 10:
            return {"type": "activity_box", "confidence": 0.8}
        elif aspect_ratio > 2.0 and area > 20000:
            return {"type": "timing_indicator", "confidence": 0.7}
        elif area > 5000 and aspect_ratio < 1.5:
            return {"type": "download_section", "confidence": 0.6}
        else:
            return {"type": "interactive_element", "confidence": 0.5}
    
    def analyze_image(self, image_path: Path) -> Dict:
        """Analyze a single image for interactive elements"""
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
        
        # Detect different types of interactive elements
        text_regions = self.detect_text_regions(image)
        highlighted_regions = self.detect_highlighted_regions(image)
        boxes = self.detect_boxes_and_borders(image)
        icons = self.detect_icons_and_symbols(image)
        
        # Combine and deduplicate regions
        all_regions = text_regions + highlighted_regions + boxes + icons
        unique_regions = self.deduplicate_regions(all_regions)
        
        # Classify each region
        classified_regions = []
        for region in unique_regions:
            classification = self.classify_interactive_element(region, image)
            x, y, w, h = region
            
            classified_regions.append({
                "bbox": {"x": x, "y": y, "width": w, "height": h},
                "area": w * h,
                "center": {"x": x + w//2, "y": y + h//2},
                "type": classification["type"],
                "confidence": classification["confidence"]
            })
        
        return {
            "filename": image_path.name,
            "page_number": page_number,
            "dimensions": {"width": width, "height": height},
            "interactive_elements": {
                "text_regions": len(text_regions),
                "highlighted_regions": len(highlighted_regions),
                "boxes": len(boxes),
                "icons": len(icons),
                "total_unique": len(unique_regions)
            },
            "regions": classified_regions
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
    
    def analyze_day(self, day: int) -> Dict:
        """Analyze all PNG files for a specific day"""
        png_files = self.find_day_pngs(day)
        
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
        
        # Save results
        output_file = self.output_dir / f"day-{day}-interactive-elements.json"
        with open(output_file, 'w') as f:
            json.dump(results, f, indent=2)
        
        # Create summary
        total_elements = sum(page["interactive_elements"]["total_unique"] for page in results["pages"])
        logger.info(f"Day {day} analysis complete: {total_elements} interactive elements detected across {len(results['pages'])} pages")
        
        return results

def main():
    parser = argparse.ArgumentParser(description="Map interactive elements in PNG files")
    parser.add_argument("--day", type=int, required=True, help="Day number to analyze")
    parser.add_argument("--source-dir", default="12-Days-to-Deming/PNGs/", help="Source directory for PNG files")
    parser.add_argument("--output", default="temp/analysis", help="Output directory for analysis results")
    
    args = parser.parse_args()
    
    detector = InteractiveElementDetector(args.source_dir, args.output)
    results = detector.analyze_day(args.day)
    
    if results:
        print(f"Analysis complete for Day {args.day}")
        print(f"Results saved to: {args.output}/day-{args.day}-interactive-elements.json")
    else:
        print(f"No results generated for Day {args.day}")

if __name__ == "__main__":
    main()
