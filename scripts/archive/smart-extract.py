#!/usr/bin/env python3
"""
smart-extract.py
Enhanced OCR extraction with better quality and text cleaning
"""

import argparse
import cv2
import numpy as np
import pytesseract
from PIL import Image
import re
from pathlib import Path
import logging

class SmartExtractor:
    def __init__(self, quality='high'):
        self.quality = quality
        self.setup_ocr_config()
    
    def setup_ocr_config(self):
        """Configure OCR based on quality setting"""
        if self.quality == 'high':
            self.tesseract_config = '--oem 3 --psm 6 -c tessedit_char_whitelist=ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789.,;:!?()[]{}- '
        else:
            self.tesseract_config = '--oem 3 --psm 6'
    
    def preprocess_image(self, image_path):
        """Enhanced image preprocessing for better OCR"""
        # Load image
        img = cv2.imread(str(image_path))
        
        # Convert to grayscale
        gray = cv2.cvtColor(img, cv2.COLOR_BGR2GRAY)
        
        # Noise reduction
        denoised = cv2.medianBlur(gray, 3)
        
        # Contrast enhancement
        clahe = cv2.createCLAHE(clipLimit=2.0, tileGridSize=(8,8))
        enhanced = clahe.apply(denoised)
        
        # Threshold to binary
        _, binary = cv2.threshold(enhanced, 0, 255, cv2.THRESH_BINARY + cv2.THRESH_OTSU)
        
        return binary
    
    def clean_ocr_text(self, text):
        """Post-process OCR text to fix common errors"""
        # Fix common OCR errors
        text = re.sub(r'\|\s+', 'I ', text)  # | -> I
        text = re.sub(r'\]\s+', 'I ', text)  # ] -> I
        text = re.sub(r'\[A\]', '[A]', text)  # Fix bracket issues
        text = re.sub(r'\[B\]', '[B]', text)
        
        # Fix line breaks in middle of words
        text = re.sub(r'(\w+)-\s*\n\s*(\w+)', r'\1\2', text)
        
        # Fix broken sentences
        text = re.sub(r'(\w+)\s*\n\s*(\w+)', r'\1 \2', text)
        
        return text
    
    def extract_with_quality(self, image_path):
        """Extract text with enhanced quality"""
        # Preprocess image
        processed_img = self.preprocess_image(image_path)
        
        # OCR with high quality settings
        text = pytesseract.image_to_string(processed_img, config=self.tesseract_config)
        
        # Clean the text
        cleaned_text = self.clean_ocr_text(text)
        
        return cleaned_text

def main():
    parser = argparse.ArgumentParser(description="Smart OCR extraction with quality improvements")
    parser.add_argument("--day", type=int, required=True, help="Day number to process")
    parser.add_argument("--quality", choices=['high', 'medium', 'fast'], default='high', help="OCR quality setting")
    parser.add_argument("--preprocess", action="store_true", help="Enable image preprocessing")
    
    args = parser.parse_args()
    
    extractor = SmartExtractor(quality=args.quality)
    
    # Process PNG files for the day
    png_dir = Path(f"12-Days-to-Deming/PNGs")
    output_dir = Path(f"temp/day-{args.day:02d}-smart")
    output_dir.mkdir(parents=True, exist_ok=True)
    
    # Find and process PNG files
    pattern = f"*Day.{args.day}*"
    png_files = sorted(png_dir.glob(pattern))
    
    print(f"Processing {len(png_files)} PNG files for Day {args.day}")
    
    for png_file in png_files:
        print(f"Processing: {png_file.name}")
        text = extractor.extract_with_quality(png_file)
        
        # Save cleaned text
        output_file = output_dir / f"{png_file.stem}-cleaned.txt"
        with open(output_file, 'w', encoding='utf-8') as f:
            f.write(text)
    
    print(f"✅ Smart extraction completed. Files saved to: {output_dir}")

if __name__ == "__main__":
    main()
