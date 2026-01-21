#!/usr/bin/env bash
set -euo pipefail

VERSION_FILE="${VERSION_FILE:-/opt/ultra-coach/VERSION}"
CHANGELOG_FILE="${CHANGELOG_FILE:-/opt/ultra-coach/CHANGELOG.md}"

usage() {
  cat <<USAGE
Uso: bin/release.sh <major|minor|patch|x.y.z> [--tag] [--dry-run]

Exemplos:
  bin/release.sh patch
  bin/release.sh 0.2.1 --tag
USAGE
}

bump_version() {
  local current="$1" bump="$2"
  IFS='.' read -r major minor patch <<<"$current"
  case "$bump" in
    major) major=$((major + 1)); minor=0; patch=0 ;;
    minor) minor=$((minor + 1)); patch=0 ;;
    patch) patch=$((patch + 1)) ;;
    *)
      if [[ "$bump" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        echo "$bump"
        return 0
      fi
      echo "Versao invalida: $bump" >&2
      exit 1
      ;;
  esac
  echo "${major}.${minor}.${patch}"
}

update_json_version() {
  local file="$1" version="$2"
  [[ -f "$file" ]] || return 0
  node -e "const fs=require('fs'); const p='$file'; const j=JSON.parse(fs.readFileSync(p,'utf8')); j.version='$version'; fs.writeFileSync(p, JSON.stringify(j,null,2)+'\\n');"
}

main() {
  local bump="${1:-}"
  local tag=0
  local dry_run=0
  shift || true

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --tag) tag=1; shift ;;
      --dry-run) dry_run=1; shift ;;
      -h|--help) usage; exit 0 ;;
      *) echo "Opcao desconhecida: $1" >&2; exit 1 ;;
    esac
  done

  [[ -n "$bump" ]] || { usage; exit 1; }
  [[ -f "$VERSION_FILE" ]] || { echo "VERSION nao encontrado em $VERSION_FILE" >&2; exit 1; }

  local current
  current="$(cat "$VERSION_FILE" | tr -d ' \t\n')"
  local next
  next="$(bump_version "$current" "$bump")"

  local last_tag
  last_tag="$(git tag --list 'v*' --sort=-v:refname | head -n1 || true)"
  local range
  if [[ -n "$last_tag" ]]; then
    range="${last_tag}..HEAD"
  else
    local root
    root="$(git rev-list --max-parents=0 HEAD)"
    range="${root}..HEAD"
  fi

  local commits
  commits="$(git log --pretty=format:'- %s (%h)' "$range" || true)"
  if [[ -z "$commits" ]]; then
    commits="- No changes"
  fi

  local date
  date="$(date -I)"

  if [[ "$dry_run" -eq 1 ]]; then
    echo "Next version: $next"
    echo "Changelog section:"
    echo "## $next - $date"
    echo "$commits"
    exit 0
  fi

  echo "$next" > "$VERSION_FILE"

  local tail_content=""
  if [[ -f "$CHANGELOG_FILE" ]]; then
    tail_content="$(awk 'NR>1 {print}' "$CHANGELOG_FILE")"
  fi

  cat > "$CHANGELOG_FILE" <<CHLOG
# Changelog

## $next - $date
$commits

$tail_content
CHLOG

  update_json_version "/opt/ultra-coach/web/package.json" "$next"
  update_json_version "/opt/ultra-coach/fit/package.json" "$next"

  if [[ "$tag" -eq 1 ]]; then
    git tag "v$next"
  fi

  echo "Version updated to $next"
}

main "$@"
