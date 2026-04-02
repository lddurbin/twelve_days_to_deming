#!/bin/bash
# Example usage of the Quarto configuration update script
# Phase 4.2 - Quarto Integration

echo "🔧 Quarto Configuration Update Examples"
echo "======================================="

# Basic usage - add specific days
echo "1. Add specific days to configuration:"
echo "python scripts/update-quarto-config.py --days 3 4 5"
echo ""

# Dry run to see what would change
echo "2. Dry run to preview changes:"
echo "python scripts/update-quarto-config.py --days 6 7 --dry-run"
echo ""

# Validate current configuration
echo "3. Validate current configuration:"
echo "python scripts/update-quarto-config.py --validate-only"
echo ""

# Add all remaining days (3-12)
echo "4. Add all remaining days:"
echo "python scripts/update-quarto-config.py --days 3 4 5 6 7 8 9 10 11 12"
echo ""

# Custom config file
echo "5. Use custom config file:"
echo "python scripts/update-quarto-config.py --config custom-quarto.yml --days 3"
echo ""

echo "Features:"
echo "- Automatically scans day directories for QMD files"
echo "- Generates appropriate part titles for each day"
echo "- Preserves existing configuration structure and formatting"
echo "- Creates backup of original configuration before updating"
echo "- Validates configuration after updates"
echo "- Supports dry-run mode for safe testing"
echo ""

echo "Day titles used:"
echo "- Day 1: The Overture"
echo "- Day 2: The Experiment on Red Beads"
echo "- Day 3: The Funnel Experiment"
echo "- Days 4-12: [Title to be determined]"
echo ""

echo "The script will:"
echo "1. Scan content/days/day-XX/ directories for .qmd files"
echo "2. Extract chapter titles from YAML frontmatter"
echo "3. Sort chapters by filename order (01-, 02-, etc.)"
echo "4. Update _quarto.yml with new part and chapter entries"
echo "5. Validate the updated configuration"
echo "6. Create backup of original file"
echo ""
