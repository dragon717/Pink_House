#!/usr/bin/env bash
#
# 时光馆发布流水线 · 离线全链路演练（不需要任何凭据、不碰真实 CloudKit）
#
# 用法：
#   bash tools/time_hall/publication/drill_offline.sh
#   bash tools/time_hall/publication/drill_offline.sh --verbose   # 打印每步完整输出
#   bash tools/time_hall/publication/drill_offline.sh --keep      # 保留工作目录以便排查
#
# 退出码：0 = 全部步骤符合预期；1 = 有步骤不符合预期。
#
# 对应设计：docs/Pink_House_TimeHall_Static_CloudKit_Design.md §9.1 / §9.2 / §9.3 / §19

set -u -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
CATALOG_DIR="$REPO_ROOT/ItemManager/Resources/TimeHall"

VERBOSE=0
KEEP=0
for arg in "$@"; do
  case "$arg" in
    --verbose) VERBOSE=1 ;;
    --keep) KEEP=1 ;;
    -h|--help) sed -n '2,17p' "${BASH_SOURCE[0]}"; exit 0 ;;
    *) echo "未知参数：$arg" >&2; exit 2 ;;
  esac
done

PY="${PYTHON:-}"
if [ -z "$PY" ]; then
  if [ -x "$HOME/.workbuddy/binaries/python/versions/3.13.12/bin/python3" ]; then
    PY="$HOME/.workbuddy/binaries/python/versions/3.13.12/bin/python3"
  else
    PY="$(command -v python3)"
  fi
fi

WORK="$(mktemp -d "${TMPDIR:-/tmp}/th_drill.XXXXXX")"
LOG_DIR="$WORK/_logs"
mkdir -p "$LOG_DIR"

INPUT="$WORK/input"
RELEASE1="$WORK/release-seq1"
RELEASE_RB="$WORK/release-rollback"
LIVE="$WORK/live"
LIVE_TAMPER="$WORK/live-tampered"
LIVE2="$WORK/live-after-rollback"

PASS=0
FAIL=0
STEP_NO=0
FAILED_STEPS=()

cleanup() {
  if [ "$KEEP" -eq 1 ]; then
    echo ""
    echo "工作目录已保留：$WORK"
  else
    rm -rf "$WORK"
  fi
}
trap cleanup EXIT

# run <标题> <期望退出码> <命令...>
# 记录实测退出码与期望是否一致，日志写入 $LOG_DIR/<n>.log
run() {
  local title="$1"
  local expected="$2"
  shift 2
  STEP_NO=$((STEP_NO + 1))
  local log="$LOG_DIR/$(printf '%02d' "$STEP_NO").log"

  "$@" >"$log" 2>&1
  local code=$?

  if [ "$code" -eq "$expected" ]; then
    printf '  %2d) %-46s ✅ 退出码 %s（符合预期）\n' "$STEP_NO" "$title" "$code"
    PASS=$((PASS + 1))
  else
    printf '  %2d) %-46s ❌ 退出码 %s，期望 %s\n' "$STEP_NO" "$title" "$code" "$expected"
    FAIL=$((FAIL + 1))
    FAILED_STEPS+=("$title")
  fi

  if [ "$VERBOSE" -eq 1 ]; then
    sed 's/^/       | /' "$log"
  fi
}

# assert <标题> <条件描述> <测试命令...>
assert() {
  local title="$1"
  local desc="$2"
  shift 2
  STEP_NO=$((STEP_NO + 1))
  if "$@" >/dev/null 2>&1; then
    printf '  %2d) %-46s ✅ %s\n' "$STEP_NO" "$title" "$desc"
    PASS=$((PASS + 1))
  else
    printf '  %2d) %-46s ❌ %s\n' "$STEP_NO" "$title" "$desc"
    FAIL=$((FAIL + 1))
    FAILED_STEPS+=("$title")
  fi
}

section() {
  echo ""
  echo "──────────────────────────────────────────────────────────────"
  echo "$1"
  echo "──────────────────────────────────────────────────────────────"
}

echo "时光馆发布流水线 · 离线全链路演练"
echo "python : $PY"
echo "工作区 : $WORK"

section "准备输入（用仓库内置 Bundle catalog 作为本地联调素材）"
mkdir -p "$INPUT"
if ! ls "$CATALOG_DIR"/catalog*.json >/dev/null 2>&1; then
  echo "❌ 找不到 $CATALOG_DIR/catalog*.json" >&2
  exit 1
fi
cp "$CATALOG_DIR"/catalog*.json "$INPUT"/
echo "  已复制 $(ls "$INPUT" | wc -l | tr -d ' ') 个 catalog 文件"

section "阶段 1 · 构建与校验产物"
run "构建发布产物（releaseSeq=1，localFixture）" 0 \
  "$PY" "$SCRIPT_DIR/build_release.py" \
    --input "$INPUT" --output "$RELEASE1" \
    --release-seq 1 --allow-unapproved-local-fixture
assert "产物含根清单" "root-index.json 已生成" test -f "$RELEASE1/root-index.json"
assert "产物含发布头草稿" "release.json 已生成" test -f "$RELEASE1/release.json"
assert "产物含分片目录" "至少有 1 个分片包" \
  bash -c "ls '$RELEASE1'/THDataPack/*.json.gz >/dev/null 2>&1 || ls '$RELEASE1'/packs/* >/dev/null 2>&1"

run "校验产物自身自洽（localFixture 仅告警）" 0 \
  "$PY" "$SCRIPT_DIR/validate_release.py" --release "$RELEASE1" --quiet

section "阶段 2 · 发布（不可变资源先上、发布头最后切换）"
run "发布演练 dry-run" 0 \
  "$PY" "$SCRIPT_DIR/publish_cloudkit.py" \
    --release "$RELEASE1" --adapter filesystem --filesystem-root "$LIVE" --quiet
assert "dry-run 无副作用" "没有留下任何已发布状态" test ! -e "$LIVE/THRelease.json"

run "发布 apply（真正写入演练目录）" 0 \
  "$PY" "$SCRIPT_DIR/publish_cloudkit.py" \
    --release "$RELEASE1" --adapter filesystem --filesystem-root "$LIVE" \
    --apply --quiet --receipt "$WORK/receipt.json"
assert "发布头已落地" "THRelease.json 存在" test -f "$LIVE/THRelease.json"
assert "根清单已落地" "root-index.json 存在" test -f "$LIVE/root-index.json"
assert "发布回执已生成" "receipt.json 存在" test -f "$WORK/receipt.json"

section "阶段 3 · 读者视角回读验证"
run "回读验证线上内容" 0 \
  "$PY" "$SCRIPT_DIR/verify_publication.py" --adapter filesystem --filesystem-root "$LIVE"

section "阶段 4 · 拒绝路径（安全边界必须拦住）"
run "重复发布号应被拒绝" 5 \
  "$PY" "$SCRIPT_DIR/publish_cloudkit.py" \
    --release "$RELEASE1" --adapter filesystem --filesystem-root "$LIVE" --apply --quiet

run "回滚号不递增应被拒绝" 4 \
  "$PY" "$SCRIPT_DIR/rollback_release.py" \
    --from-release "$RELEASE1" --output "$WORK/rb-invalid" \
    --release-seq 1 --reason "演练：发布号未递增" --published-root "$LIVE"

run "localFixture 产物禁止发到 CloudKit" 4 \
  "$PY" "$SCRIPT_DIR/publish_cloudkit.py" \
    --release "$RELEASE1" --adapter cloudkit --environment development --quiet

echo ""
echo "  ── 篡改检出（在副本上做，不污染已发布状态）──"
cp -R "$LIVE" "$LIVE_TAMPER"
FIRST_PACK="$(find "$LIVE_TAMPER/THDataPack" -name '*.json.gz' | head -1)"
if [ -n "$FIRST_PACK" ]; then
  "$PY" - "$FIRST_PACK" >/dev/null 2>&1 <<'PYEOF'
import gzip, json, sys

path = sys.argv[1]
raw = json.loads(gzip.decompress(open(path, "rb").read()))


def tamper(node):
    if isinstance(node, dict):
        for key, value in node.items():
            if isinstance(value, str) and value:
                node[key] = value + "-tampered"
                return True
            if tamper(value):
                return True
    elif isinstance(node, list):
        for item in node:
            if tamper(item):
                return True
    return False


if not tamper(raw):
    sys.exit(1)
open(path, "wb").write(gzip.compress(json.dumps(raw, sort_keys=True).encode("utf-8"), mtime=0))
PYEOF
  run "回读应检出被篡改的分片" 3 \
    "$PY" "$SCRIPT_DIR/verify_publication.py" \
      --adapter filesystem --filesystem-root "$LIVE_TAMPER"
else
  echo "  跳过：演练目录里没有找到分片包"
fi

section "阶段 5 · 回滚（发布号继续递增，不倒退）"
run "生成回滚产物（releaseSeq=5）" 0 \
  "$PY" "$SCRIPT_DIR/rollback_release.py" \
    --from-release "$RELEASE1" --output "$RELEASE_RB" \
    --release-seq 5 --published-root "$LIVE" \
    --reason "演练：线上版本字段错位，回滚到 releaseSeq=1 的内容" --apply
run "校验回滚产物" 0 \
  "$PY" "$SCRIPT_DIR/validate_release.py" --release "$RELEASE_RB" --quiet
run "发布回滚产物到干净演练目录" 0 \
  "$PY" "$SCRIPT_DIR/publish_cloudkit.py" \
    --release "$RELEASE_RB" --adapter filesystem --filesystem-root "$LIVE2" \
    --apply --quiet
run "回读确认回滚后的版本" 0 \
  "$PY" "$SCRIPT_DIR/verify_publication.py" --adapter filesystem --filesystem-root "$LIVE2"
assert "发布号已推进到 5" "线上 releaseSeq 已递增" \
  bash -c "grep -q '\"releaseSeq\"[^0-9]*5' '$LIVE2/THRelease.json'"

section "结果"
echo "  通过 $PASS 项，失败 $FAIL 项"
if [ "$FAIL" -gt 0 ]; then
  echo ""
  echo "  未通过的步骤："
  for name in "${FAILED_STEPS[@]}"; do
    echo "    - $name"
  done
  echo ""
  if [ "$KEEP" -eq 0 ]; then
    echo "  提示：加 --keep 可保留工作目录，日志在 \$WORK/_logs/"
  fi
  exit 1
fi

echo ""
echo "  ✅ 发布流水线全链路演练通过：构建 → 校验 → 发布 → 回读 → 拒绝路径 → 回滚 → 再发布"
echo "     说明：本演练使用 filesystem 适配器，未访问真实 CloudKit，不需要任何凭据。"
exit 0
