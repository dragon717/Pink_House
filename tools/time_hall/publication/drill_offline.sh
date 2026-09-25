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
# 本脚本**不自带也不引用**任何随 App 版本变动的资源目录：
# 演练夹具就地生成（见「准备输入」），因此旧馆资源被移除后演练依然可跑。

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

section "准备输入（自带联调夹具；不依赖任何随 App 版本变动的资源目录）"
mkdir -p "$INPUT"
# 历史沿革：本步骤原先直接 cp `ItemManager/Resources/TimeHall/catalog*.json`。
# 时光馆旧馆于 d84d983d 被移除后该目录已不存在，演练卡在第一步（2026-09-25 修）。
# 现在改为**就地生成**夹具：日期与 id 全部写死，保证同一版本下 payloadHash 可复现；
# 夹具形状与 build_release 期望的 V3 整馆 catalog 一致（entityType -> 数组字段）。
"$PY" - "$INPUT" <<'PYEOF'
import json
import sys
from pathlib import Path

target = Path(sys.argv[1]) / "catalog.json"
# 注意：文件名必须等于 sources.yaml 中该品牌的 resourceName（pink-house -> "catalog"）。
fixture = {
    "version": 3,
    "brand": "PINK HOUSE",
    "events": [
        {"id": "news-drill-001", "publishedOn": "2026-09-12", "title": "演练夹具：资讯一"},
        {"id": "news-drill-002", "publishedOn": "2026-09-14", "title": "演练夹具：资讯二"},
    ],
    "commerceItems": [
        {"id": "drill-item-001", "observedAt": "2026-09-12", "name": "演练夹具：商品一"},
    ],
    "catalogues": [
        {"id": "drill-cat-001", "observedAt": "2026-09-14", "name": "演练夹具：目录一"},
    ],
}
target.write_text(json.dumps(fixture, ensure_ascii=False, indent=2), encoding="utf-8")
print("  已生成夹具 {}".format(target))
PYEOF
if ! ls "$INPUT"/catalog*.json >/dev/null 2>&1; then
  echo "❌ 夹具生成失败，无法继续演练" >&2
  exit 1
fi
echo "  已准备 $(ls "$INPUT" | wc -l | tr -d ' ') 个 catalog 文件"

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

section "阶段 6 · 商店目录整包分片（时光馆「商店」内容 / 店家上新）"
# 商店目录走整包单分片：entityType=shop-catalog、brandID=shaonv-xinyuan（运营自有内容源，
# 不与画册品牌共用 —— 根清单 brands 按 brandID 去重）。夹具自洽：引用全部包内可解析。
SHOP_FIXTURE="$WORK/shop-catalog.json"
SHOP_BAD="$WORK/shop-catalog-dangling.json"
"$PY" - "$SHOP_FIXTURE" "$SHOP_BAD" <<'PYEOF'
import json
import sys
from pathlib import Path

good = {
    "version": 1,
    "shops": [{"id": "shop-drill", "name": "演练店家"}],
    "series": [
        {"id": "series-drill", "shopID": "shop-drill", "name": "2026 秋冬", "year": 2026, "month": 9}
    ],
    "products": [
        {
            "id": "product-drill",
            "shopID": "shop-drill",
            "seriesID": "series-drill",
            "name": "演练商品",
            "category": "JSK",
        }
    ],
    "variants": [{"id": "variant-drill", "productID": "product-drill", "color": "黑", "size": "M"}],
    "saleEvents": [
        {
            "id": "event-drill",
            "productID": "product-drill",
            "type": "reservation",
            "price": 1280,
            "deposit": 300,
            "balance": 980,
            "currency": "CNY",
        }
    ],
}
# 反例：商品指向包内不存在的系列 → 结构校验必须拒绝
bad = json.loads(json.dumps(good))
bad["products"][0]["seriesID"] = "series-missing"

Path(sys.argv[1]).write_text(json.dumps(good, ensure_ascii=False, indent=2), encoding="utf-8")
Path(sys.argv[2]).write_text(json.dumps(bad, ensure_ascii=False, indent=2), encoding="utf-8")
PYEOF

RELEASE_SHOP="$WORK/release-shop"
LIVE_SHOP="$WORK/live-shop"

run "构建含商店目录的发布产物" 0 \
  "$PY" "$SCRIPT_DIR/build_release.py" \
    --input "$INPUT" --shop-catalog "$SHOP_FIXTURE" --output "$RELEASE_SHOP" \
    --release-seq 1 --allow-unapproved-local-fixture
assert "根清单含商店目录分片" "shaonv-xinyuan/shop-catalog/all 已声明" \
  bash -c "grep -q 'shaonv-xinyuan/shop-catalog/all' '$RELEASE_SHOP/root-index.json'"
assert "商店分片记录数正确" "recordCount = 5（店家/系列/商品/规格/销售记录）" \
  bash -c "grep -q '\"recordCount\":5' '$RELEASE_SHOP/root-index.json'"

run "校验含商店目录的产物" 0 \
  "$PY" "$SCRIPT_DIR/validate_release.py" --release "$RELEASE_SHOP" --quiet
run "发布含商店目录的产物（filesystem）" 0 \
  "$PY" "$SCRIPT_DIR/publish_cloudkit.py" \
    --release "$RELEASE_SHOP" --adapter filesystem --filesystem-root "$LIVE_SHOP" \
    --apply --quiet
run "读者回读含商店目录的线上内容" 0 \
  "$PY" "$SCRIPT_DIR/verify_publication.py" --adapter filesystem --filesystem-root "$LIVE_SHOP"

run "商店目录悬空引用应被拒绝" 5 \
  "$PY" "$SCRIPT_DIR/build_release.py" \
    --input "$INPUT" --shop-catalog "$SHOP_BAD" --output "$WORK/release-bad" \
    --release-seq 1 --allow-unapproved-local-fixture

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
