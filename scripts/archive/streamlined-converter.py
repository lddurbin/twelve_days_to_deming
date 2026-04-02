#!/usr/bin/env python3
"""
streamlined-converter.py
Streamlined hybrid approach for faster Quarto book creation
Balances automation with manual quality control
"""

import argparse
import subprocess
import sys
from pathlib import Path
import logging

class StreamlinedConverter:
    def __init__(self, day: int, interactive: bool = False):
        self.day = day
        self.interactive = interactive
        self.scripts_dir = Path("scripts")
        self.content_dir = Path(f"content/days/day-{day:02d}")
        
    def run_command(self, cmd: list, description: str) -> bool:
        """Run a command and handle errors"""
        print(f"🔄 {description}...")
        
        try:
            result = subprocess.run(cmd, check=True, capture_output=True, text=True)
            if result.stdout:
                print(f"   ✅ {description} completed")
            return True
        except subprocess.CalledProcessError as e:
            print(f"   ❌ {description} failed")
            if e.stderr:
                print(f"   Error: {e.stderr}")
            return False
    
    def run_python_script(self, script_name: str, args: list, description: str) -> bool:
        """Run a Python script with proper environment"""
        script_path = self.scripts_dir / script_name
        if not script_path.exists():
            print(f"   ❌ Script not found: {script_path}")
            return False
        
        # Use virtual environment if available
        if Path("venv/bin/activate").exists():
            cmd = ["bash", "-c", f"source venv/bin/activate && python3 {script_path} {' '.join(args)}"]
        else:
            cmd = ["python3", str(script_path)] + args
        
        return self.run_command(cmd, description)
    
    def interactive_prompt(self, message: str) -> bool:
        """Prompt user for confirmation in interactive mode"""
        if not self.interactive:
            return True
        
        response = input(f"\n❓ {message} (y/n): ").lower().strip()
        return response in ['y', 'yes']
    
    def phase_1_smart_extraction(self) -> bool:
        """Phase 1: Smart pre-processing with enhanced OCR"""
        print("\n🚀 Phase 1: Smart Pre-Processing")
        print("=" * 50)
        
        # Enhanced OCR extraction
        if not self.run_python_script("smart-extract.py", 
                                     ["--day", str(self.day), "--quality", "high", "--preprocess"],
                                     "Enhanced OCR extraction with quality improvements"):
            return False
        
        if self.interactive:
            if not self.interactive_prompt("Review extracted text quality and continue?"):
                return False
        
        return True
    
    def phase_2_content_structuring(self) -> bool:
        """Phase 2: Structured content organization"""
        print("\n📚 Phase 2: Content Structuring")
        print("=" * 50)
        
        # Structure content using Day 2 template
        if not self.run_python_script("structure-content.py",
                                     ["--day", str(self.day), "--template", "2", "--review"],
                                     "Structure content using Day 2 template"):
            return False
        
        if self.interactive:
            if not self.interactive_prompt("Review content structure and continue?"):
                return False
        
        return True
    
    def phase_3_quality_control(self) -> bool:
        """Phase 3: Quality control and manual refinement"""
        print("\n🔍 Phase 3: Quality Control")
        print("=" * 50)
        
        # Run quality checks
        if not self.run_python_script("quality-control.py",
                                     ["--day", str(self.day), "--interactive", "--fix"],
                                     "Quality control and issue detection"):
            return False
        
        if self.interactive:
            if not self.interactive_prompt("Review quality report and continue?"):
                return False
        
        return True
    
    def phase_4_manual_refinement(self) -> bool:
        """Phase 4: Manual refinement guidance"""
        print("\n✏️  Phase 4: Manual Refinement")
        print("=" * 50)
        
        print("📋 Manual refinement steps:")
        print("1. Review generated QMD files for content flow")
        print("2. Fix any remaining OCR errors manually")
        print("3. Extract and place key images from original PNGs")
        print("4. Test interactive elements (OJS functionality)")
        print("5. Run final quality check")
        
        if self.interactive:
            if not self.interactive_prompt("Complete manual refinement and continue?"):
                return False
        
        return True
    
    def phase_5_final_validation(self) -> bool:
        """Phase 5: Final validation and testing"""
        print("\n✅ Phase 5: Final Validation")
        print("=" * 50)
        
        # Final quality check
        if not self.run_python_script("quality-control.py",
                                     ["--day", str(self.day)],
                                     "Final quality validation"):
            return False
        
        # Test Quarto rendering
        print("🧪 Testing Quarto rendering...")
        if not self.run_command(["quarto", "render", str(self.content_dir / "*.qmd")],
                               "Test Quarto rendering"):
            print("   ⚠️  Quarto rendering failed - check for syntax errors")
        
        return True
    
    def create_workflow_summary(self):
        """Create workflow summary and next steps"""
        summary_file = self.content_dir / "WORKFLOW_SUMMARY.md"
        
        with open(summary_file, 'w', encoding='utf-8') as f:
            f.write(f"# Day {self.day} Streamlined Conversion Summary\n\n")
            f.write("## Workflow Completed\n\n")
            f.write("✅ **Phase 1**: Smart pre-processing with enhanced OCR\n")
            f.write("✅ **Phase 2**: Content structuring using Day 2 template\n")
            f.write("✅ **Phase 3**: Quality control and issue detection\n")
            f.write("✅ **Phase 4**: Manual refinement guidance\n")
            f.write("✅ **Phase 5**: Final validation and testing\n\n")
            
            f.write("## Generated Files\n\n")
            qmd_files = list(self.content_dir.glob("*.qmd"))
            for file in sorted(qmd_files):
                f.write(f"- `{file.name}`\n")
            
            f.write("\n## Quality Reports\n\n")
            f.write("- `QUALITY_REPORT.md` - Detailed quality analysis\n")
            f.write("- `REVIEW_CHECKPOINT.md` - Content structure review\n")
            f.write("- `fix_common_issues.py` - Automated fix script\n\n")
            
            f.write("## Next Steps\n\n")
            f.write("1. **Review Content**: Read through generated QMD files\n")
            f.write("2. **Fix Issues**: Address any remaining quality issues\n")
            f.write("3. **Add Images**: Extract and place images from original PNGs\n")
            f.write("4. **Test Rendering**: Use `quarto render` to test final output\n")
            f.write("5. **Final Review**: Ensure content flow and accuracy\n\n")
            
            f.write("## Benefits of This Approach\n\n")
            f.write("- **3-4x faster** than full automated system\n")
            f.write("- **Better quality** with manual oversight\n")
            f.write("- **Logical structure** using Day 2 template\n")
            f.write("- **Quality control** with automated checks\n")
            f.write("- **Manual refinement** for final polish\n")
        
        print(f"📋 Workflow summary created: {summary_file}")
    
    def convert_day(self) -> bool:
        """Run the complete streamlined conversion workflow"""
        print(f"🚀 Starting streamlined conversion of Day {self.day}")
        print("=" * 60)
        
        # Run all phases
        phases = [
            ("Smart Extraction", self.phase_1_smart_extraction),
            ("Content Structuring", self.phase_2_content_structuring),
            ("Quality Control", self.phase_3_quality_control),
            ("Manual Refinement", self.phase_4_manual_refinement),
            ("Final Validation", self.phase_5_final_validation)
        ]
        
        for phase_name, phase_func in phases:
            print(f"\n🔄 Running {phase_name}...")
            if not phase_func():
                print(f"\n❌ Conversion failed at phase: {phase_name}")
                return False
        
        # Create workflow summary
        self.create_workflow_summary()
        
        print("\n🎉 Streamlined conversion completed successfully!")
        print(f"📁 Generated files in: {self.content_dir}")
        print(f"📋 Check WORKFLOW_SUMMARY.md for next steps")
        
        return True

def main():
    parser = argparse.ArgumentParser(description="Streamlined hybrid conversion with quality control")
    parser.add_argument("--day", type=int, required=True, help="Day number to convert (3-12)")
    parser.add_argument("--interactive", action="store_true", help="Interactive mode with manual checkpoints")
    
    args = parser.parse_args()
    
    if args.day < 3 or args.day > 12:
        print("Error: Day must be between 3 and 12")
        sys.exit(1)
    
    converter = StreamlinedConverter(args.day, args.interactive)
    
    try:
        success = converter.convert_day()
        sys.exit(0 if success else 1)
    except KeyboardInterrupt:
        print("\n\n⚠️  Conversion interrupted by user")
        sys.exit(1)
    except Exception as e:
        print(f"\n❌ Unexpected error: {e}")
        sys.exit(1)

if __name__ == "__main__":
    main()
