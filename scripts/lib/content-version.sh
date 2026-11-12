#!/usr/bin/env bash
#
# content-version.sh — the single definition of which site files a validation
# record covers, and of `content_version`, a hash of those files. Sourced by
# both the writer (scripts/validate-transcription.sh, which compares those
# files and stamps the hash into workflow/validation/results/*.yml) and the
# reader (scripts/check-validation-staleness.sh, which recomputes the hash from
# the repo and compares). One definition, two consumers, the same shape as
# scripts/lib/scorer-version.sh and for the same reason (#737).
#
# Why this exists (#837): a result records three inputs. `scorer_version` says
# which comparator produced it, `source_sha256` which PDF it read. Nothing said
# which *site content* it was compared against, so a PR could apply fifty
# corrections to a day, leave its record untouched, and every check stayed
# green. That is what happened to Day 3 between #832 and #836. The PDF can't be
# checked in CI (it is gitignored and local-only), but the content can: it is
# in git.
#
# What a record covers is decided here and nowhere else:
#
#   day-NN       every .qmd in content/days/day-NN/
#   <name>       the chapters workflow/validation/<name>-manifest.yml lists,
#                under its content_dir
#
# minus any page workflow/validation/no-source.yml declares to have no source
# PDF (#802). The hash covers the resulting list as well as the files' bytes,
# because adding a chapter to a manifest restales the counts exactly as
# editing one does.
#
# Deliberately NOT included in the hash: this file, the manifests and
# no-source.yml themselves. Only the list they produce matters; a comment
# edit to any of them changes nothing a record says.
#
# .github/workflows/validation-staleness.yml must have a `paths:` entry
# matching every file any record covers, plus the manifests and no-source.yml
# that decide the list, or an edit won't trigger the check that catches it.
# tests/test_content_version.py enforces that.
#
# Usage:
#   source "$REPO_ROOT/scripts/lib/content-version.sh"
#   version=$(compute_content_version "$REPO_ROOT" day-03)

# Read a manifest's identity and its chapter list.
# Prints PDF_FILE=..., CONTENT_DIR=..., then one CHAPTER=... per chapter.
#
# The chapter list is why this reads more than two keys since #802. It used to
# be ignored and the content directory globbed instead, which quietly made
# "every .qmd sitting in this folder" the definition of what a source PDF is
# answerable for. Two chapters in content/appendix/ do not come from
# P.Appendix.09Feb22.pdf at all, so every paragraph of both was reported
# unsourced against it — 69 of that run's 70 unsourced findings, indistinguishable
# from the one real one. The manifest already enumerated its chapters for
# check-structure.sh; taking the list from there rather than from the filesystem
# means a chapter is compared against a PDF because someone said it came from
# that PDF, not because of where it happens to sit on disk.
read_manifest() {
  local manifest="$1"
  if ! command -v ruby &>/dev/null; then
    echo "Error: ruby not found (needed for YAML parsing)" >&2
    return 1
  fi
  ruby -ryaml -e '
    begin
      data = YAML.safe_load(File.read(ARGV[0]))
    rescue => e
      $stderr.puts "Error parsing manifest #{ARGV[0]}: #{e.message}"
      exit 1
    end
    puts "PDF_FILE=#{data["pdf_file"] || ""}"
    puts "CONTENT_DIR=#{data["content_dir"] || ""}"
    (data["chapters"] || []).each { |ch| puts "CHAPTER=#{ch["file"]}" }
  ' "$manifest"
}

# Print the repo-relative path of every page declared to have no source PDF.
#
# These are site originals — pages written for this edition rather than
# transcribed from Neave — and they are declared in one file rather than simply
# left out of every manifest, because "nobody wrote down where this came from"
# and "someone checked and the answer is nowhere" are indistinguishable from
# absence alone. See workflow/validation/no-source.yml and #802.
read_no_source() {
  local repo_root=$1
  local register="$repo_root/workflow/validation/no-source.yml"
  if [[ ! -f "$register" ]]; then
    echo "Error: no-source register not found at ${register#"$repo_root/"}" >&2
    return 1
  fi
  if ! command -v ruby &>/dev/null; then
    echo "Error: ruby not found (needed for YAML parsing)" >&2
    return 1
  fi
  ruby -ryaml -e '
    begin
      data = YAML.safe_load(File.read(ARGV[0]))
    rescue => e
      $stderr.puts "Error parsing #{ARGV[0]}: #{e.message}"
      exit 1
    end
    (data["pages"] || {}).each_key { |path| puts path }
  ' "$register"
}

# Print every repo-relative .qmd path a record draws from, before the
# no-source register is applied, sorted. $2 is the record's name: its results
# file's basename without `.yml` (day-03, appendix-main, welcome, ...).
#
# Sorted because the comparator builds its paragraph pool by concatenating
# files in this order, and the glob this replaced was sorted.
content_candidates() {
  local repo_root=$1 record=$2
  local out f line

  if [[ "$record" =~ ^day-[0-9][0-9]$ ]]; then
    local dir="$repo_root/content/days/$record"
    if [[ ! -d "$dir" ]]; then
      echo "Error: no content directory at content/days/$record" >&2
      return 1
    fi
    for f in "$dir"/*.qmd; do
      [[ -e "$f" ]] && out+="${f#"$repo_root/"}"$'\n'
    done
  else
    local manifest="$repo_root/workflow/validation/${record}-manifest.yml"
    if [[ ! -f "$manifest" ]]; then
      echo "Error: no manifest at ${manifest#"$repo_root/"}" >&2
      return 1
    fi
    local parsed content_dir=""
    parsed=$(read_manifest "$manifest") || return 1
    while IFS= read -r line; do
      case "$line" in
        CONTENT_DIR=*) content_dir="${line#CONTENT_DIR=}" ;;
      esac
    done <<< "$parsed"
    if [[ -z "$content_dir" ]]; then
      echo "Error: ${manifest#"$repo_root/"} declares no content_dir" >&2
      return 1
    fi
    while IFS= read -r line; do
      case "$line" in
        CHAPTER=*)
          f="${line#CHAPTER=}"
          if [[ "$content_dir" == "." ]]; then
            out+="$f"$'\n'
          else
            out+="$content_dir/$f"$'\n'
          fi
          ;;
      esac
    done <<< "$parsed"
  fi

  [[ -n "$out" ]] && printf '%s' "$out" | LC_ALL=C sort
  return 0
}

# Split a record's candidates into what it compares and what it holds out.
# Prints one `compare <path>` or `skip <path>` line per candidate, in
# content_candidates order.
partition_content_files() {
  local repo_root=$1 record=$2
  local candidates no_source rel

  candidates=$(content_candidates "$repo_root" "$record") || return 1
  no_source=$(read_no_source "$repo_root") || return 1

  [[ -n "$candidates" ]] || return 0
  while IFS= read -r rel; do
    if [[ -n "$no_source" ]] && grep -qxF -- "$rel" <<< "$no_source"; then
      printf 'skip %s\n' "$rel"
    else
      printf 'compare %s\n' "$rel"
    fi
  done <<< "$candidates"
}

# Print the repo-relative paths a record actually compares, one per line.
compared_content_files() {
  local partition
  partition=$(partition_content_files "$1" "$2") || return 1
  [[ -n "$partition" ]] || return 0
  sed -n 's/^compare //p' <<< "$partition"
}

# Print a single hash covering a record's compared files: their paths and
# their bytes.
#
# Hashes a sorted "<path> <blob-hash>" manifest, as compute_scorer_version
# does: including the path means a chapter joining or leaving the list moves
# the digest. Content hashes, not commit SHAs, so an uncommitted local edit
# restales a record just as a merged one does.
compute_content_version() {
  local repo_root=$1 record=$2
  local files f ok=1

  files=$(compared_content_files "$repo_root" "$record") || return 1
  if [[ -z "$files" ]]; then
    echo "content-version.sh: record '$record' covers no files — nothing to hash." >&2
    return 1
  fi

  while IFS= read -r f; do
    if [[ ! -f "$repo_root/$f" ]]; then
      echo "content-version.sh: '$f' is part of record '$record' but does not exist." >&2
      ok=0
    fi
  done <<< "$files"
  if [[ "$ok" -ne 1 ]]; then
    echo "content-version.sh: refusing to compute a content_version from an incomplete file list." >&2
    return 1
  fi

  while IFS= read -r f; do
    printf '%s %s\n' "$f" "$(git -C "$repo_root" hash-object "$repo_root/$f")"
  done <<< "$files" | LC_ALL=C sort | git -C "$repo_root" hash-object --stdin
}

# The command that refreshes a record, for error messages.
content_record_command() {
  local record=$1
  if [[ "$record" =~ ^day-([0-9][0-9])$ ]]; then
    echo "./scripts/validate-transcription.sh $((10#${BASH_REMATCH[1]}))"
  else
    echo "./scripts/validate-transcription.sh --manifest $record"
  fi
}
