#!/bin/bash

# Usage: ./new_day_from_file.sh 02 day02_chapters.txt

DAY_NUM=$1
CHAPTER_FILE=$2
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DAY_DIR="content/days/day-$DAY_NUM"
CHAPTER_PATH="$SCRIPT_DIR/$CHAPTER_FILE"

if [ -z "$DAY_NUM" ] || [ -z "$CHAPTER_FILE" ]; then
  echo "Usage: $0 <day-number> <chapter-list-file>"
  exit 1
fi

if [ ! -d "$DAY_DIR" ]; then
  echo "Directory $DAY_DIR does not exist!"
  exit 1
fi

if [ ! -f "$CHAPTER_PATH" ]; then
  echo "Chapter list file $CHAPTER_PATH does not exist!"
  exit 1
fi

# Read the first line as the day name/title, rest as chapters
DAY_NAME=""
CHAPTERS=()
while IFS= read -r line || [ -n "$line" ]; do
  if [ -z "$DAY_NAME" ]; then
    DAY_NAME="$line"
  else
    [ -z "$line" ] && continue
    CHAPTERS+=("$line")
  fi
done < "$CHAPTER_PATH"

for chapter in "${CHAPTERS[@]}"; do
  TARGET="$DAY_DIR/$chapter.qmd"
  cp assets/templates/chapter-template.qmd "$TARGET"
  sed -i '' "s/DAY X/DAY $DAY_NUM/g" "$TARGET"
  sed -i '' "s/CHAPTER TITLE HERE/$(echo $chapter | sed 's/-/ /g' | awk '{for(i=1;i<=NF;i++)$i=toupper(substr($i,1,1)) substr($i,2)}1')/g" "$TARGET"
done

echo "Created chapters for Day $DAY_NUM:"
ls "$DAY_DIR"
echo "\nReminder: Please update your _quarto.yml file to include the new chapters in the book navigation." 