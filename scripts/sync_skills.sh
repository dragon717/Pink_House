#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
TRAE_ROOT="${REPO_ROOT}/.trae/skills"
CODEX_ROOT="${CODEX_HOME:-$HOME/.codex}/skills"
MAP_FILE="${SCRIPT_DIR}/skill_sync_map.tsv"
MODE="to-codex"
DRY_RUN=0
TIMESTAMP="$(date '+%Y%m%d-%H%M%S')"
BACKUP_ROOT="${REPO_ROOT}/.trae/backups/skills-sync-${TIMESTAMP}"
CREATED=0
UPDATED=0
SKIPPED=0
WARNINGS=0
BACKUP_USED=0

usage() {
  cat <<'EOF'
Usage: scripts/sync_skills.sh [--to-codex | --to-trae | --bidirectional] [--dry-run]

Options:
  --to-codex       Sync project Trae skills into ~/.codex/skills
  --to-trae        Sync ~/.codex/skills back into project .trae/skills
  --bidirectional  Compare both sides and sync the newer version to the older side
  --dry-run        Print planned changes without writing files
  --help           Show this message
EOF
}

log() {
  printf '%s\n' "$*"
}

warn() {
  printf 'WARN: %s\n' "$*" >&2
  WARNINGS=$((WARNINGS + 1))
}

mtime() {
  local path="$1"
  if [ ! -e "$path" ]; then
    echo 0
    return
  fi
  if stat -f %m "$path" >/dev/null 2>&1; then
    stat -f %m "$path"
  else
    stat -c %Y "$path"
  fi
}

latest_mtime_in_dir() {
  local dir="$1"
  local max_ts=0
  local ts=0
  local file=""
  if [ ! -d "$dir" ]; then
    echo 0
    return
  fi
  while IFS= read -r -d '' file; do
    ts="$(mtime "$file")"
    if [ "$ts" -gt "$max_ts" ]; then
      max_ts="$ts"
    fi
  done < <(find "$dir" -type f -print0 2>/dev/null)
  if [ "$max_ts" -eq 0 ]; then
    mtime "$dir"
  else
    echo "$max_ts"
  fi
}

name_line() {
  local name="$1"
  if [[ "$name" =~ ^[a-z0-9-]+$ ]]; then
    printf 'name: %s\n' "$name"
  else
    printf 'name: "%s"\n' "$name"
  fi
}

rewrite_skill_name() {
  local src="$1"
  local target_name="$2"
  local out="$3"
  awk -v target_name="$target_name" '
    function emit_name() {
      if (target_name ~ /^[a-z0-9-]+$/) {
        print "name: " target_name
      } else {
        escaped = target_name
        gsub(/"/, "\\\"", escaped)
        print "name: \"" escaped "\""
      }
    }
    NR == 1 && $0 == "---" {
      in_frontmatter = 1
      print
      next
    }
    in_frontmatter && !replaced && $0 ~ /^name:/ {
      emit_name()
      replaced = 1
      next
    }
    in_frontmatter && $0 == "---" {
      if (!replaced) {
        emit_name()
        replaced = 1
      }
      in_frontmatter = 0
      print
      next
    }
    {
      print
    }
  ' "$src" > "$out"
}

backup_dir() {
  local src_dir="$1"
  local side="$2"
  local skill_label="$3"
  if [ ! -d "$src_dir" ]; then
    return
  fi
  local backup_dir="${BACKUP_ROOT}/${side}/${skill_label}"
  mkdir -p "$backup_dir"
  rsync -a "$src_dir"/ "$backup_dir"/
  BACKUP_USED=1
}

prepare_temp_copy() {
  local src_dir="$1"
  local target_name="$2"
  local temp_dir="$3"
  mkdir -p "$temp_dir"
  rsync -a --delete "$src_dir"/ "$temp_dir"/
  if [ -f "${temp_dir}/SKILL.md" ]; then
    local temp_skill="${temp_dir}/.SKILL.md.tmp"
    rewrite_skill_name "${temp_dir}/SKILL.md" "$target_name" "$temp_skill"
    mv "$temp_skill" "${temp_dir}/SKILL.md"
  fi
}

sync_dir() {
  local src_dir="$1"
  local src_display="$2"
  local target_dir="$3"
  local target_display="$4"
  local backup_side="$5"
  local skill_label="$6"
  local temp_dir
  local target_existed=0
  temp_dir="$(mktemp -d)"
  if [ -d "$target_dir" ]; then
    target_existed=1
  fi
  prepare_temp_copy "$src_dir" "$target_display" "$temp_dir"
  if [ -d "$target_dir" ] && diff -qr "$temp_dir" "$target_dir" >/dev/null 2>&1; then
    log "skip ${skill_label}: ${src_display} -> ${target_display} (内容一致)"
    SKIPPED=$((SKIPPED + 1))
    rm -rf "$temp_dir"
    return
  fi
  if [ "$DRY_RUN" -eq 1 ]; then
    if [ "$target_existed" -eq 1 ]; then
      log "update ${skill_label}: ${src_display} -> ${target_display}"
      UPDATED=$((UPDATED + 1))
    else
      log "create ${skill_label}: ${src_display} -> ${target_display}"
      CREATED=$((CREATED + 1))
    fi
    rm -rf "$temp_dir"
    return
  fi
  if [ "$target_existed" -eq 1 ]; then
    backup_dir "$target_dir" "$backup_side" "$skill_label"
  fi
  mkdir -p "$target_dir"
  rsync -a --delete "$temp_dir"/ "$target_dir"/
  if [ "$target_existed" -eq 1 ]; then
    UPDATED=$((UPDATED + 1))
    log "updated ${skill_label}: ${src_display} -> ${target_display}"
  else
    CREATED=$((CREATED + 1))
    log "created ${skill_label}: ${src_display} -> ${target_display}"
  fi
  rm -rf "$temp_dir"
}

sync_pair() {
  local trae_folder="$1"
  local codex_folder="$2"
  local trae_name="$3"
  local codex_name="$4"
  local trae_dir="${TRAE_ROOT}/${trae_folder}"
  local codex_dir="${CODEX_ROOT}/${codex_folder}"
  local trae_ts codex_ts
  trae_ts="$(latest_mtime_in_dir "$trae_dir")"
  codex_ts="$(latest_mtime_in_dir "$codex_dir")"

  case "$MODE" in
    to-codex)
      if [ ! -d "$trae_dir" ]; then
        warn "${trae_folder} 缺少 Trae 源目录"
        return
      fi
      if [ "$trae_ts" -gt "$codex_ts" ] || [ ! -d "$codex_dir" ]; then
        sync_dir "$trae_dir" "$trae_folder" "$codex_dir" "$codex_name" "codex" "$codex_folder"
      else
        log "skip ${codex_folder}: Codex 侧更新或相同"
        SKIPPED=$((SKIPPED + 1))
      fi
      ;;
    to-trae)
      if [ ! -d "$codex_dir" ]; then
        warn "${codex_folder} 缺少 Codex 源目录"
        return
      fi
      if [ "$codex_ts" -gt "$trae_ts" ] || [ ! -d "$trae_dir" ]; then
        sync_dir "$codex_dir" "$codex_folder" "$trae_dir" "$trae_name" "trae" "$trae_folder"
      else
        log "skip ${trae_folder}: Trae 侧更新或相同"
        SKIPPED=$((SKIPPED + 1))
      fi
      ;;
    bidirectional)
      if [ ! -d "$trae_dir" ] && [ ! -d "$codex_dir" ]; then
        warn "${trae_folder}/${codex_folder} 两侧都不存在"
        return
      fi
      if [ "$trae_ts" -gt "$codex_ts" ]; then
        sync_dir "$trae_dir" "$trae_folder" "$codex_dir" "$codex_name" "codex" "$codex_folder"
      elif [ "$codex_ts" -gt "$trae_ts" ]; then
        sync_dir "$codex_dir" "$codex_folder" "$trae_dir" "$trae_name" "trae" "$trae_folder"
      else
        log "skip ${trae_folder}/${codex_folder}: 双侧时间一致"
        SKIPPED=$((SKIPPED + 1))
      fi
      ;;
    *)
      warn "未知模式: ${MODE}"
      return 1
      ;;
  esac
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --to-codex)
      MODE="to-codex"
      ;;
    --to-trae)
      MODE="to-trae"
      ;;
    --bidirectional)
      MODE="bidirectional"
      ;;
    --dry-run)
      DRY_RUN=1
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      printf 'Unknown argument: %s\n\n' "$1" >&2
      usage >&2
      exit 1
      ;;
  esac
  shift
done

if [ ! -f "$MAP_FILE" ]; then
  printf 'Missing mapping file: %s\n' "$MAP_FILE" >&2
  exit 1
fi

while IFS=$'\t' read -r trae_folder codex_folder trae_name codex_name; do
  if [ -z "${trae_folder}" ] || [[ "${trae_folder}" == \#* ]]; then
    continue
  fi
  sync_pair "$trae_folder" "$codex_folder" "$trae_name" "$codex_name"
done < "$MAP_FILE"

log ""
log "mode=${MODE} dry_run=${DRY_RUN} created=${CREATED} updated=${UPDATED} skipped=${SKIPPED} warnings=${WARNINGS}"
if [ "$DRY_RUN" -eq 0 ] && [ "$CREATED" -eq 0 ] && [ "$UPDATED" -eq 0 ]; then
  log "没有需要写入的变更。"
fi
if [ "$DRY_RUN" -eq 0 ] && [ "$BACKUP_USED" -eq 1 ]; then
  log "备份目录: ${BACKUP_ROOT}"
fi
