#!/usr/bin/env python3
"""
structure-content.py
Structure extracted content using Day 2 as template with manual review points
"""

import argparse
import json
import re
from pathlib import Path
from typing import List, Dict, Tuple
import logging

class ContentStructurer:
    def __init__(self, day: int, template_day: int = 2):
        self.day = day
        self.template_day = template_day
        self.template_dir = Path(f"content/days/day-{template_day:02d}")
        self.input_dir = Path(f"temp/day-{day:02d}-smart")
        self.output_dir = Path(f"content/days/day-{day:02d}")
        
    def analyze_template_structure(self):
        """Analyze Day 2 structure to use as template"""
        template_files = list(self.template_dir.glob("*.qmd"))
        structure = {}
        
        for file in template_files:
            with open(file, 'r', encoding='utf-8') as f:
                content = f.read()
                
            # Extract title
            title_match = re.search(r'title:\s*"([^"]+)"', content)
            title = title_match.group(1) if title_match else file.stem
            
            # Analyze content structure
            structure[file.name] = {
                'title': title,
                'has_activities': 'pause for thought' in content.lower(),
                'has_interactive': 'ojs' in content,
                'has_images': 'assets/images' in content,
                'content_type': self.classify_content_type(content)
            }
        
        return structure
    
    def classify_content_type(self, content):
        """Classify content type based on patterns"""
        content_lower = content.lower()
        
        if 'activity' in content_lower or 'exercise' in content_lower:
            return 'activity'
        elif 'introduction' in content_lower or 'overview' in content_lower:
            return 'introduction'
        elif 'conclusion' in content_lower or 'summary' in content_lower:
            return 'conclusion'
        else:
            return 'narrative'
    
    def group_extracted_content(self):
        """Group extracted content into logical chapters"""
        text_files = list(self.input_dir.glob("*-cleaned.txt"))
        
        # Read all extracted text
        all_content = []
        for file in sorted(text_files):
            with open(file, 'r', encoding='utf-8') as f:
                content = f.read().strip()
                if content:
                    all_content.append({
                        'file': file.name,
                        'content': content,
                        'page_num': self.extract_page_number(file.name)
                    })
        
        # Group content into logical chapters
        chapters = self.create_logical_chapters(all_content)
        return chapters
    
    def extract_page_number(self, filename):
        """Extract page number from filename"""
        match = re.search(r'page_(\d+)', filename)
        return int(match.group(1)) if match else 0
    
    def create_logical_chapters(self, content_list):
        """Group content into logical chapters based on content analysis"""
        chapters = []
        current_chapter = None
        
        for item in content_list:
            content = item['content']
            
            # Detect chapter boundaries
            if self.is_chapter_start(content):
                if current_chapter:
                    chapters.append(current_chapter)
                
                current_chapter = {
                    'title': self.extract_chapter_title(content),
                    'content': [item],
                    'page_range': [item['page_num']]
                }
            else:
                if current_chapter:
                    current_chapter['content'].append(item)
                    current_chapter['page_range'].append(item['page_num'])
                else:
                    # Start new chapter if none exists
                    current_chapter = {
                        'title': f"Chapter {len(chapters) + 1}",
                        'content': [item],
                        'page_range': [item['page_num']]
                    }
        
        if current_chapter:
            chapters.append(current_chapter)
        
        return chapters
    
    def is_chapter_start(self, content):
        """Detect if content represents a chapter start"""
        # Look for chapter indicators
        chapter_indicators = [
            r'^day\s+\d+',
            r'^chapter\s+\d+',
            r'^introduction',
            r'^overview',
            r'^activity\s+\d+',
            r'^exercise\s+\d+',
            r'^major\s+activity',
            r'^pause\s+for\s+thought',
            r'^understanding\s+variation',
            r'^funnel\s+experiment',
            r'^back\s+to\s+the\s+western',
            r'^at\s+the\s+ford',
            r'^the\s+importance\s+of\s+time',
            r'^six\s+processes',
            r'^control\s+chart'
        ]
        
        # Check first few lines for chapter indicators
        lines = content.split('\n')[:3]
        for line in lines:
            line = line.strip().lower()
            if any(re.search(pattern, line) for pattern in chapter_indicators):
                return True
        
        return False
    
    def extract_chapter_title(self, content):
        """Extract chapter title from content"""
        lines = content.split('\n')
        
        # Look for specific patterns first
        for line in lines[:5]:
            line = line.strip()
            if 'understanding variation' in line.lower():
                return "Understanding Variation"
            elif 'funnel experiment' in line.lower():
                return "The Funnel Experiment"
            elif 'major activity' in line.lower():
                return "Major Activity"
            elif 'pause for thought' in line.lower():
                return "Pause for Thought"
            elif 'western electric' in line.lower():
                return "Back to the Western Electric Company"
            elif 'ford motor' in line.lower():
                return "At the Ford Motor Company"
            elif 'importance of time' in line.lower():
                return "The Importance of Time"
            elif 'six processes' in line.lower():
                return "Six Processes"
            elif 'control chart' in line.lower():
                return "Control Chart + Brain"
        
        # Fallback to first reasonable line
        for line in lines[:5]:
            line = line.strip()
            if len(line) > 10 and len(line) < 100:  # Reasonable title length
                return line
        
        return "Untitled Chapter"
    
    def generate_structured_files(self, chapters):
        """Generate structured QMD files based on template"""
        self.output_dir.mkdir(parents=True, exist_ok=True)
        
        template_structure = self.analyze_template_structure()
        
        for i, chapter in enumerate(chapters, 1):
            # Choose appropriate template
            template_type = self.select_template_type(chapter)
            
            # Generate QMD file
            qmd_content = self.create_qmd_file(chapter, template_type, i)
            
            # Save file
            filename = f"{i:02d}-{self.sanitize_filename(chapter['title'])}.qmd"
            output_file = self.output_dir / filename
            
            with open(output_file, 'w', encoding='utf-8') as f:
                f.write(qmd_content)
            
            print(f"Generated: {filename}")
    
    def select_template_type(self, chapter):
        """Select appropriate template type for chapter"""
        content_text = ' '.join([item['content'] for item in chapter['content']]).lower()
        
        if 'activity' in content_text or 'exercise' in content_text:
            return 'activity'
        elif 'introduction' in content_text or 'overview' in content_text:
            return 'introduction'
        else:
            return 'narrative'
    
    def create_qmd_file(self, chapter, template_type, chapter_num):
        """Create QMD file content based on template type"""
        title = chapter['title']
        
        # Base YAML header
        yaml_header = f"""---
title: "{title}"
execute:
  echo: false
---

```{{r}}
# R setup for all chapters (edit as needed)
knitr::knit_hooks$set(crop = knitr::hook_pdfcrop)
source(here::here("R/functions/main-functions.R"))
```

"""
        
        # Add content based on template type
        if template_type == 'activity':
            content = self.create_activity_content(chapter)
        elif template_type == 'introduction':
            content = self.create_introduction_content(chapter)
        else:
            content = self.create_narrative_content(chapter)
        
        return yaml_header + content
    
    def create_activity_content(self, chapter):
        """Create activity-style content"""
        content = f"# {chapter['title']}\n\n"
        
        # Add main content
        for item in chapter['content']:
            content += f"{item['content']}\n\n"
        
        # Add interactive elements
        content += """
```{ojs}
viewof activity_response = Inputs.textarea({placeholder: "Type your comments here.", rows: 10})
```

<button class="btn btn-primary" type="button" data-bs-toggle="collapse" data-bs-target="#collapse_feedback" aria-expanded="false" aria-controls="collapse_feedback">
Show Commentary
</button>
<div class="collapse" id="collapse_feedback">
Activity feedback or commentary goes here.
</div>

```{ojs download_all}
download_button = html`<button class="btn btn-primary" type="button">Download Your Notes</button>`
```

```{ojs download_trigger}
import { downloadNotes } from "../../../assets/scripts/functions.js"
download_button.onclick = () => {
  downloadNotes([viewof activity_response], "activity_notes.txt");
};
```
"""
        return content
    
    def create_introduction_content(self, chapter):
        """Create introduction-style content"""
        content = f"# {chapter['title']}\n\n"
        
        for item in chapter['content']:
            content += f"{item['content']}\n\n"
        
        return content
    
    def create_narrative_content(self, chapter):
        """Create narrative-style content"""
        content = f"# {chapter['title']}\n\n"
        
        for item in chapter['content']:
            content += f"{item['content']}\n\n"
        
        return content
    
    def sanitize_filename(self, title):
        """Sanitize title for filename"""
        # Remove special characters and replace with hyphens
        sanitized = re.sub(r'[^\w\s-]', '', title)
        sanitized = re.sub(r'[-\s]+', '-', sanitized)
        return sanitized.lower()
    
    def create_review_checkpoint(self, chapters):
        """Create manual review checkpoint"""
        review_file = self.output_dir / "REVIEW_CHECKPOINT.md"
        
        with open(review_file, 'w', encoding='utf-8') as f:
            f.write(f"# Day {self.day} Content Structure Review\n\n")
            f.write("## Generated Chapters\n\n")
            
            for i, chapter in enumerate(chapters, 1):
                f.write(f"### Chapter {i}: {chapter['title']}\n")
                f.write(f"- Pages: {min(chapter['page_range'])}-{max(chapter['page_range'])}\n")
                f.write(f"- Content items: {len(chapter['content'])}\n\n")
            
            f.write("## Manual Review Required\n\n")
            f.write("1. **Chapter Titles**: Review and adjust chapter titles\n")
            f.write("2. **Content Flow**: Ensure logical progression\n")
            f.write("3. **Interactive Elements**: Verify activity formatting\n")
            f.write("4. **Image Placeholders**: Add actual images\n\n")
            f.write("## Next Steps\n\n")
            f.write("1. Review generated QMD files\n")
            f.write("2. Adjust chapter structure if needed\n")
            f.write("3. Run quality control script\n")
        
        print(f"📋 Review checkpoint created: {review_file}")

def main():
    parser = argparse.ArgumentParser(description="Structure content using template with manual review")
    parser.add_argument("--day", type=int, required=True, help="Day number to structure")
    parser.add_argument("--template", type=int, default=2, help="Template day to use (default: 2)")
    parser.add_argument("--review", action="store_true", help="Create review checkpoint")
    
    args = parser.parse_args()
    
    structurer = ContentStructurer(args.day, args.template)
    
    print(f"🔍 Analyzing template structure from Day {args.template}")
    template_structure = structurer.analyze_template_structure()
    
    print(f"📝 Grouping extracted content for Day {args.day}")
    chapters = structurer.group_extracted_content()
    
    print(f"📄 Generating structured files...")
    structurer.generate_structured_files(chapters)
    
    if args.review:
        structurer.create_review_checkpoint(chapters)
    
    print(f"✅ Content structuring completed!")
    print(f"📁 Generated files in: {structurer.output_dir}")
    print(f"📊 Created {len(chapters)} chapters from extracted content")

if __name__ == "__main__":
    main()
