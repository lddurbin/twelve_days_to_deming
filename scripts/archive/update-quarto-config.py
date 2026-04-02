#!/usr/bin/env python3
"""
Quarto Configuration Update Script
Phase 4.2 of the PNG Conversion Plan

This script automatically updates _quarto.yml with new chapters for Days 3-12,
maintaining consistent part/chapter structure and preserving existing theme and formatting.
"""

import os
import re
import sys
import argparse
import yaml
from pathlib import Path
from typing import List, Dict, Any, Optional
from dataclasses import dataclass


@dataclass
class ChapterInfo:
    """Information about a chapter file"""
    path: str
    title: Optional[str] = None
    order: int = 0


@dataclass
class DayInfo:
    """Information about a day's content"""
    day_number: int
    title: str
    chapters: List[ChapterInfo]


class QuartoConfigUpdater:
    """Main class for updating Quarto configuration"""
    
    def __init__(self, config_path: str = "_quarto.yml"):
        self.config_path = Path(config_path)
        self.content_dir = Path("content/days")
        self.day_titles = {
            1: "The Overture",
            2: "The Experiment on Red Beads",
            3: "The Funnel Experiment",
            4: "Day 4: [Title to be determined]",
            5: "Day 5: [Title to be determined]",
            6: "Day 6: [Title to be determined]",
            7: "Day 7: [Title to be determined]",
            8: "Day 8: [Title to be determined]",
            9: "Day 9: [Title to be determined]",
            10: "Day 10: [Title to be determined]",
            11: "Day 11: [Title to be determined]",
            12: "Day 12: [Title to be determined]"
        }
        
    def load_config(self) -> Dict[str, Any]:
        """Load the current Quarto configuration"""
        if not self.config_path.exists():
            raise FileNotFoundError(f"Configuration file {self.config_path} not found")
            
        with open(self.config_path, 'r', encoding='utf-8') as f:
            content = f.read()
            
        try:
            config = yaml.safe_load(content)
            return config
        except yaml.YAMLError as e:
            raise ValueError(f"Invalid YAML in {self.config_path}: {e}")
    
    def save_config(self, config: Dict[str, Any]):
        """Save the updated Quarto configuration"""
        # Create a backup of the original file
        backup_path = self.config_path.with_suffix('.yml.backup')
        if self.config_path.exists():
            import shutil
            shutil.copy2(self.config_path, backup_path)
            print(f"Backup created: {backup_path}")
        
        with open(self.config_path, 'w', encoding='utf-8') as f:
            # Use standard YAML with proper formatting
            yaml.dump(config, f, default_flow_style=False, sort_keys=False, indent=2, width=120)
    
    
    def scan_day_content(self, day_number: int) -> DayInfo:
        """Scan a day directory for QMD files and extract chapter information"""
        day_dir = self.content_dir / f"day-{day_number:02d}"
        
        if not day_dir.exists():
            return DayInfo(day_number, self.day_titles[day_number], [])
        
        chapters = []
        qmd_files = sorted(day_dir.glob("*.qmd"))
        
        for qmd_file in qmd_files:
            # Extract chapter info
            chapter_path = f"content/days/day-{day_number:02d}/{qmd_file.name}"
            
            # Try to extract title from file
            title = self._extract_title_from_file(qmd_file)
            
            # Determine order from filename
            order = self._extract_order_from_filename(qmd_file.name)
            
            chapters.append(ChapterInfo(
                path=chapter_path,
                title=title,
                order=order
            ))
        
        # Sort chapters by order
        chapters.sort(key=lambda x: x.order)
        
        return DayInfo(day_number, self.day_titles[day_number], chapters)
    
    def _extract_title_from_file(self, qmd_file: Path) -> Optional[str]:
        """Extract title from QMD file frontmatter"""
        try:
            with open(qmd_file, 'r', encoding='utf-8') as f:
                content = f.read()
            
            # Look for YAML frontmatter
            if content.startswith('---'):
                yaml_end = content.find('---', 3)
                if yaml_end != -1:
                    yaml_content = content[3:yaml_end]
                    try:
                        frontmatter = yaml.safe_load(yaml_content)
                        return frontmatter.get('title')
                    except yaml.YAMLError:
                        pass
        except Exception:
            pass
        
        return None
    
    def _extract_order_from_filename(self, filename: str) -> int:
        """Extract order number from filename (e.g., '01-title.qmd' -> 1)"""
        match = re.match(r'^(\d+)', filename)
        return int(match.group(1)) if match else 999
    
    def update_config_with_days(self, config: Dict[str, Any], days: List[int]) -> Dict[str, Any]:
        """Update configuration with specified days"""
        # Ensure we have the book structure
        if 'book' not in config:
            config['book'] = {}
        
        if 'chapters' not in config['book']:
            config['book']['chapters'] = []
        
        chapters_list = config['book']['chapters']
        
        # Find existing parts and track which days are already included
        existing_days = set()
        updated_chapters = []
        
        for item in chapters_list:
            if isinstance(item, dict):
                # Check if this is a part entry
                part_key = None
                for key in item.keys():
                    if key.startswith("part:"):
                        part_key = key
                        break
                
                if part_key:
                    # This is a part - check if it's one of the days we're processing
                    part_title = part_key.replace("part: ", "")
                    day_match = re.search(r'Day (\d+)', part_title)
                    if day_match:
                        day_num = int(day_match.group(1))
                        existing_days.add(day_num)
                        
                        # If this day is in our list to update, skip it (we'll add the new version)
                        if day_num in days:
                            print(f"Day {day_num} already exists, will be updated")
                            continue
                    
                    # Keep existing part
                    updated_chapters.append(item)
                else:
                    # This is some other dict entry
                    updated_chapters.append(item)
            else:
                # This is a regular chapter (like index.qmd)
                updated_chapters.append(item)
        
        # Add new days
        for day_num in sorted(days):
            if day_num in existing_days:
                continue  # Skip if already processed above
            
            day_info = self.scan_day_content(day_num)
            if not day_info.chapters:
                print(f"No QMD files found for Day {day_num}, skipping")
                continue
            
            # Create part entry in the correct format
            part_entry = {
                f"part: {day_info.title}": {
                    "chapters": [chapter.path for chapter in day_info.chapters]
                }
            }
            updated_chapters.append(part_entry)
            
            print(f"Added Day {day_num}: {len(day_info.chapters)} chapters")
        
        # Update the configuration
        config['book']['chapters'] = updated_chapters
        
        return config
    
    def validate_config(self, config: Dict[str, Any]) -> List[str]:
        """Validate the updated configuration"""
        errors = []
        
        # Check required fields
        if 'book' not in config:
            errors.append("Missing 'book' section")
        else:
            if 'title' not in config['book']:
                errors.append("Missing book title")
            if 'chapters' not in config['book']:
                errors.append("Missing chapters list")
        
        # Check format section
        if 'format' not in config:
            errors.append("Missing 'format' section")
        
        # Validate chapter paths
        if 'book' in config and 'chapters' in config['book']:
            for item in config['book']['chapters']:
                if isinstance(item, str):
                    # Regular chapter file
                    if not Path(item).exists() and item != "index.qmd":
                        errors.append(f"Chapter file not found: {item}")
                elif isinstance(item, dict):
                    # Part with chapters
                    for part_key, part_value in item.items():
                        if part_key.startswith("part:") and isinstance(part_value, dict):
                            if 'chapters' in part_value:
                                for chapter_path in part_value['chapters']:
                                    if not Path(chapter_path).exists():
                                        errors.append(f"Chapter file not found: {chapter_path}")
        
        return errors


def main():
    """Main CLI interface"""
    parser = argparse.ArgumentParser(description="Update Quarto configuration with new chapters")
    parser.add_argument("--days", nargs="+", type=int, default=list(range(3, 13)),
                       help="Day numbers to add (default: 3-12)")
    parser.add_argument("--config", default="_quarto.yml", help="Path to Quarto config file")
    parser.add_argument("--dry-run", action="store_true", help="Show what would be changed without updating")
    parser.add_argument("--validate-only", action="store_true", help="Only validate current configuration")
    
    args = parser.parse_args()
    
    try:
        updater = QuartoConfigUpdater(args.config)
        
        if args.validate_only:
            print("Validating current configuration...")
            config = updater.load_config()
            errors = updater.validate_config(config)
            
            if errors:
                print("❌ Configuration validation failed:")
                for error in errors:
                    print(f"  - {error}")
                sys.exit(1)
            else:
                print("✅ Configuration is valid")
                sys.exit(0)
        
        print(f"Updating Quarto configuration for Days: {args.days}")
        
        # Load current configuration
        config = updater.load_config()
        
        # Update with new days
        updated_config = updater.update_config_with_days(config, args.days)
        
        # Validate updated configuration
        errors = updater.validate_config(updated_config)
        if errors:
            print("❌ Updated configuration validation failed:")
            for error in errors:
                print(f"  - {error}")
            sys.exit(1)
        
        if args.dry_run:
            print("Dry run - would update configuration with:")
            # Use standard YAML formatting for dry run
            print(yaml.dump(updated_config, default_flow_style=False, sort_keys=False, indent=2, width=120))
        else:
            # Save updated configuration
            updater.save_config(updated_config)
            print(f"✅ Configuration updated successfully in {args.config}")
            
            # Show summary
            total_chapters = 0
            for item in updated_config.get('book', {}).get('chapters', []):
                if isinstance(item, dict):
                    for part_key, part_value in item.items():
                        if part_key.startswith("part:") and isinstance(part_value, dict):
                            chapters = part_value.get('chapters', [])
                            total_chapters += len(chapters)
                elif isinstance(item, str):
                    total_chapters += 1
            
            print(f"Total chapters in configuration: {total_chapters}")
    
    except Exception as e:
        print(f"❌ Error: {e}")
        sys.exit(1)


if __name__ == "__main__":
    main()
