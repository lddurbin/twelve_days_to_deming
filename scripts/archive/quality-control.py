#!/usr/bin/env python3
"""
quality-control.py
Interactive quality control and manual refinement
"""

import argparse
import json
import re
from pathlib import Path
from typing import List, Dict, Tuple
import logging

class QualityController:
    def __init__(self, day: int):
        self.day = day
        self.content_dir = Path(f"content/days/day-{day:02d}")
        self.issues = []
        self.suggestions = []
    
    def run_quality_checks(self):
        """Run comprehensive quality checks"""
        print(f"🔍 Running quality checks for Day {self.day}")
        
        qmd_files = list(self.content_dir.glob("*.qmd"))
        if not qmd_files:
            print("❌ No QMD files found!")
            return False
        
        print(f"📄 Found {len(qmd_files)} QMD files to check")
        
        for file in qmd_files:
            print(f"\n🔍 Checking: {file.name}")
            self.check_file_quality(file)
        
        self.generate_quality_report()
        return True
    
    def check_file_quality(self, file_path):
        """Check quality of individual QMD file"""
        with open(file_path, 'r', encoding='utf-8') as f:
            content = f.read()
        
        # Check YAML header
        self.check_yaml_header(file_path, content)
        
        # Check content structure
        self.check_content_structure(file_path, content)
        
        # Check OCR quality
        self.check_ocr_quality(file_path, content)
        
        # Check interactive elements
        self.check_interactive_elements(file_path, content)
        
        # Check image references
        self.check_image_references(file_path, content)
    
    def check_yaml_header(self, file_path, content):
        """Check YAML header quality"""
        if not content.startswith('---'):
            self.issues.append(f"{file_path.name}: Missing YAML header")
            return
        
        yaml_end = content.find('---', 3)
        if yaml_end == -1:
            self.issues.append(f"{file_path.name}: Incomplete YAML header")
            return
        
        yaml_content = content[3:yaml_end]
        
        # Check for required fields
        if 'title:' not in yaml_content:
            self.issues.append(f"{file_path.name}: Missing title in YAML")
        elif 'title: ""' in yaml_content:
            self.issues.append(f"{file_path.name}: Empty title")
        
        if 'execute:' not in yaml_content:
            self.suggestions.append(f"{file_path.name}: Consider adding execute block")
    
    def check_content_structure(self, file_path, content):
        """Check content structure and organization"""
        # Check for headings
        headings = re.findall(r'^#+\s+(.+)$', content, re.MULTILINE)
        if not headings:
            self.issues.append(f"{file_path.name}: No headings found")
        elif len(headings) < 2:
            self.suggestions.append(f"{file_path.name}: Consider adding more headings")
        
        # Check for proper heading hierarchy
        heading_levels = re.findall(r'^(#+)\s+', content, re.MULTILINE)
        if heading_levels:
            levels = [len(level) for level in heading_levels]
            if max(levels) - min(levels) > 2:
                self.suggestions.append(f"{file_path.name}: Consider flattening heading hierarchy")
        
        # Check for content length
        text_content = re.sub(r'^---.*?---', '', content, flags=re.DOTALL)
        text_content = re.sub(r'```.*?```', '', text_content, flags=re.DOTALL)
        text_content = re.sub(r'<[^>]+>', '', text_content)
        
        if len(text_content.strip()) < 100:
            self.issues.append(f"{file_path.name}: Very short content")
        elif len(text_content.strip()) < 300:
            self.suggestions.append(f"{file_path.name}: Consider expanding content")
    
    def check_ocr_quality(self, file_path, content):
        """Check for common OCR quality issues"""
        # Check for OCR artifacts
        ocr_artifacts = [
            (r'\|\s+', '| character (should be I)'),
            (r'\]\s+', '] character (should be I)'),
            (r'\[A\]', 'Bracket formatting issue'),
            (r'\[B\]', 'Bracket formatting issue'),
        ]
        
        for pattern, description in ocr_artifacts:
            if re.search(pattern, content):
                self.issues.append(f"{file_path.name}: OCR artifact - {description}")
        
        # Check for broken words
        broken_words = re.findall(r'\w+-\s*\n\s*\w+', content)
        if broken_words:
            self.issues.append(f"{file_path.name}: Broken words found: {broken_words[:3]}")
        
        # Check for excessive line breaks
        excessive_breaks = re.findall(r'\n\s*\n\s*\n', content)
        if len(excessive_breaks) > 3:
            self.suggestions.append(f"{file_path.name}: Consider reducing excessive line breaks")
    
    def check_interactive_elements(self, file_path, content):
        """Check interactive elements quality"""
        # Check for OJS blocks
        ojs_blocks = re.findall(r'```\{ojs\}.*?```', content, re.DOTALL)
        if ojs_blocks:
            for block in ojs_blocks:
                if 'Inputs.textarea' in block and 'placeholder' not in block:
                    self.issues.append(f"{file_path.name}: OJS textarea missing placeholder")
        
        # Check for download functionality
        if 'downloadNotes' in content and 'viewof' not in content:
            self.issues.append(f"{file_path.name}: Download function without input variables")
        
        # Check for collapsible sections
        if 'data-bs-toggle="collapse"' in content:
            if 'collapse' not in content:
                self.issues.append(f"{file_path.name}: Collapse toggle without target")
    
    def check_image_references(self, file_path, content):
        """Check image reference quality"""
        # Check for image placeholders
        placeholder_images = re.findall(r'!\[.*?\]\([^)]+placeholder[^)]+\)', content)
        if placeholder_images:
            self.suggestions.append(f"{file_path.name}: {len(placeholder_images)} image placeholders need manual replacement")
        
        # Check for broken image paths
        broken_images = re.findall(r'!\[.*?\]\([^)]*day-XX[^)]*\)', content)
        if broken_images:
            self.issues.append(f"{file_path.name}: Broken image paths with day-XX placeholder")
        
        # Check for missing alt text
        images_without_alt = re.findall(r'!\[\]\([^)]+\)', content)
        if images_without_alt:
            self.suggestions.append(f"{file_path.name}: Images without alt text")
    
    def generate_quality_report(self):
        """Generate comprehensive quality report"""
        report_file = self.content_dir / "QUALITY_REPORT.md"
        
        with open(report_file, 'w', encoding='utf-8') as f:
            f.write(f"# Day {self.day} Quality Control Report\n\n")
            
            f.write("## Issues Found\n\n")
            if self.issues:
                for issue in self.issues:
                    f.write(f"- ❌ {issue}\n")
            else:
                f.write("- ✅ No critical issues found\n")
            
            f.write("\n## Suggestions\n\n")
            if self.suggestions:
                for suggestion in self.suggestions:
                    f.write(f"- 💡 {suggestion}\n")
            else:
                f.write("- ✅ No suggestions at this time\n")
            
            f.write(f"\n## Summary\n\n")
            f.write(f"- **Total Issues**: {len(self.issues)}\n")
            f.write(f"- **Total Suggestions**: {len(self.suggestions)}\n")
            f.write(f"- **Files Checked**: {len(list(self.content_dir.glob('*.qmd')))}\n")
            
            f.write("\n## Next Steps\n\n")
            f.write("1. **Fix Critical Issues**: Address all ❌ issues first\n")
            f.write("2. **Review Suggestions**: Consider implementing 💡 suggestions\n")
            f.write("3. **Manual Review**: Read through content for flow and accuracy\n")
            f.write("4. **Image Placement**: Replace placeholders with actual images\n")
            f.write("5. **Test Rendering**: Use `quarto render` to test final output\n")
        
        print(f"📋 Quality report generated: {report_file}")
        print(f"📊 Found {len(self.issues)} issues and {len(self.suggestions)} suggestions")
    
    def create_fix_script(self):
        """Create automated fix script for common issues"""
        fix_script = self.content_dir / "fix_common_issues.py"
        
        with open(fix_script, 'w', encoding='utf-8') as f:
            f.write('''#!/usr/bin/env python3
"""
fix_common_issues.py
Automated fixes for common quality issues
"""

import re
from pathlib import Path

def fix_ocr_artifacts(content):
    """Fix common OCR artifacts"""
    # Fix | -> I
    content = re.sub(r'\\|\\s+', 'I ', content)
    # Fix ] -> I  
    content = re.sub(r'\\]\\s+', 'I ', content)
    # Fix broken words
    content = re.sub(r'(\\w+)-\\s*\\n\\s*(\\w+)', r'\\1\\2', content)
    return content

def fix_excessive_line_breaks(content):
    """Fix excessive line breaks"""
    content = re.sub(r'\\n\\s*\\n\\s*\\n+', '\\n\\n', content)
    return content

def main():
    content_dir = Path(".")
    qmd_files = list(content_dir.glob("*.qmd"))
    
    for file in qmd_files:
        print(f"Fixing: {file.name}")
        
        with open(file, 'r', encoding='utf-8') as f:
            content = f.read()
        
        # Apply fixes
        content = fix_ocr_artifacts(content)
        content = fix_excessive_line_breaks(content)
        
        with open(file, 'w', encoding='utf-8') as f:
            f.write(content)
    
    print("✅ Common issues fixed!")

if __name__ == "__main__":
    main()
''')
        
        print(f"🔧 Fix script created: {fix_script}")

def main():
    parser = argparse.ArgumentParser(description="Interactive quality control and manual refinement")
    parser.add_argument("--day", type=int, required=True, help="Day number to check")
    parser.add_argument("--interactive", action="store_true", help="Interactive mode with manual review")
    parser.add_argument("--fix", action="store_true", help="Create automated fix script")
    
    args = parser.parse_args()
    
    controller = QualityController(args.day)
    
    if controller.run_quality_checks():
        if args.fix:
            controller.create_fix_script()
        
        if args.interactive:
            print("\n🔍 Interactive Review Mode")
            print("Review the quality report and make manual adjustments as needed.")
            print("Run the fix script to address common issues automatically.")
        
        print(f"\n✅ Quality control completed for Day {args.day}")
        print(f"📋 Check the quality report for detailed findings")

if __name__ == "__main__":
    main()
