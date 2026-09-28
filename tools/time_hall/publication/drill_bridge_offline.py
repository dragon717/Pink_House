#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""运营桥接器（`ops_publish_bridge.py`）· 离线全链路演练。

不需要任何凭据、不碰真实 CloudKit：全程用 `filesystem` 适配器 + `localFixture` 环境。

## 为什么单独有一份，而不是并进 `drill_offline.sh`

`drill_offline.sh` 证明的是**发布流水线**（build → publish → verify → rollback）本身好用。
这份证明的是 Mac 工作台与流水线之间的**那一层协议**：

  · 冻结请求 → NDJSON 事件流 → 回执 → 结论，字段与退出码是否与
    `ShopCatalogPublishProtocol.swift` 逐条对得上；
  · R07（基线只读核对）与 R09（结果待确认先查询、禁止换号重发）在桥接侧是否真的成立；
  · 拒绝路径（摘要不符 / 环境适配器错配 / 协议版本不符 / 缺字段 / 缺图 / 同号重发）
    是否**每个都给出正确退出码 + 可读结论**，而不是 traceback。

## 用法

    python3 tools/time_hall/publication/drill_bridge_offline.py
    python3 tools/time_hall/publication/drill_bridge_offline.py --verbose
    python3 tools/time_hall/publication/drill_bridge_offline.py --keep

退出码：0 = 全部符合预期；1 = 有步骤不符合预期；2 = 环境/夹具准备失败。

对应文档：`docs/PinkHouse_千牛式上新方案_离线阅读.html` §5.2 / §6 / R07 / R08 / R09。
"""

from __future__ import annotations

import argparse
import hashlib
import json
import subprocess
import sys
import tarfile
import tempfile
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple

HERE = Path(__file__).resolve().parent
BRIDGE = HERE / "ops_publish_bridge.py"

SCHEMA_VERSION = 1

# 与 `ops_publish_bridge.py` 同一张表（那份是唯一实现，这里只用来断言）
EXIT_OK = 0
EXIT_USAGE = 2
EXIT_VALIDATION = 3
EXIT_REFUSED = 4
EXIT_CONFLICT = 5

VERBOSE = False
KEEP = False

PASS = 0
FAIL = 0
STEP_NO = 0
FAILED: List[str] = []


# ------------------------------------------------------------------ 断言脚手架

def step(title: str, expected: int, actual: int, detail: str = "") -> None:
    global PASS, FAIL, STEP_NO
    STEP_NO += 1
    if expected == actual:
        PASS += 1
        print("  {:2d}) {:<48} ✅ 退出码 {}（符合预期）".format(STEP_NO, title, actual))
    else:
        FAIL += 1
        FAILED.append(title)
        print("  {:2d}) {:<48} ❌ 退出码 {}，期望 {}".format(STEP_NO, title, actual, expected))
    if detail and (VERBOSE or expected != actual):
        for line in detail.strip().splitlines():
            print("       | {}".format(line))


def check(title: str, ok: bool, desc: str, detail: str = "") -> None:
    global PASS, FAIL, STEP_NO
    STEP_NO += 1
    if ok:
        PASS += 1
        print("  {:2d}) {:<48} ✅ {}".format(STEP_NO, title, desc))
    else:
        FAIL += 1
        FAILED.append(title)
        print("  {:2d}) {:<48} ❌ {}".format(STEP_NO, title, desc))
    if detail and (VERBOSE or not ok):
        for line in detail.strip().splitlines():
            print("       | {}".format(line))


def section(title: str) -> None:
    print("")
    print("─" * 62)
    print(title)
    print("─" * 62)


# ------------------------------------------------------------------ 桥接调用

def run_bridge(mode: str, request: Path) -> Tuple[int, List[Dict[str, Any]], str]:
    """跑一次桥接器，解析回 NDJSON 事件列表。"""
    proc = subprocess.run(
        [sys.executable, str(BRIDGE), "--mode", mode, "--request", str(request)],
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        encoding="utf-8",
        errors="replace",
    )
    events: List[Dict[str, Any]] = []
    for raw in proc.stdout.splitlines():
        line = raw.strip()
        if not line:
            continue
        if not line.startswith("{"):
            # 桥接器**只**该吐 NDJSON；非 JSON 行说明有人往 stdout 里打了别的东西
            events.append({"type": "__non_json__", "raw": line})
            continue
        events.append(json.loads(line))
    return proc.returncode, events, proc.stdout


def result_event(events: List[Dict[str, Any]]) -> Optional[Dict[str, Any]]:
    for event in reversed(events):
        if event.get("type") == "result":
            return event
    return None


def outcome_of(events: List[Dict[str, Any]]) -> Optional[str]:
    event = result_event(events)
    return event.get("outcome") if event else None


def message_of(events: List[Dict[str, Any]]) -> str:
    event = result_event(events)
    return str(event.get("message") or "") if event else ""


def non_json_lines(events: List[Dict[str, Any]]) -> List[str]:
    return [str(e.get("raw")) for e in events if e.get("type") == "__non_json__"]


# ------------------------------------------------------------------ 请求文件

def write_request(
    path: Path,
    work: Path,
    *,
    release_seq: int = 7,
    payload_hash: str,
    archive: Path,
    environment: str = "localFixture",
    adapter: Optional[str] = None,
    dry_run: bool = False,
    schema_version: int = SCHEMA_VERSION,
    request_id: str = "drill-req-1",
    drop_fields: Tuple[str, ...] = (),
    base_seq: Optional[int] = None,
    base_hash: Optional[str] = None,
    baseline_ack: bool = True,
) -> Path:
    """写一份冻结请求 JSON。

    ⚠️ `baseline_ack` 默认 True 是**有意**的：绝大多数用例要验的是别的路径，
    带着「基线不一致」的干扰会让那些断言变得不干净。R07 的闸门自己有专门的用例
    （阶段 3b），在那里显式传 False 来证明「不一致就真的被拒」。
    """
    request: Dict[str, Any] = {
        "schemaVersion": schema_version,
        "requestID": request_id,
        "jobID": "drill-job-1",
        "draftID": "drill-draft-1",
        "draftRevision": 5,
        "baseReleaseSeq": base_seq,
        "baseRootIndexHash": base_hash,
        "baselineAcknowledged": baseline_ack,
        "targetEnvironment": environment,
        "adapter": adapter or ("filesystem" if environment == "localFixture" else "cloudkit"),
        "releaseSeq": release_seq,
        "inputDirectory": str(work / "input"),
        "archivePath": str(archive),
        "outputDirectory": str(work / "release-seq{}".format(release_seq)),
        "receiptPath": str(work / "receipt-seq{}.json".format(release_seq)),
        "filesystemRoot": str(work / "live"),
        "dryRun": dry_run,
        "payloadHash": payload_hash,
        "createdAt": "2026-09-27T00:00:00Z",
    }
    for key in drop_fields:
        request.pop(key, None)
    path.write_text(json.dumps(request, ensure_ascii=False, indent=2), encoding="utf-8")
    return path


# ------------------------------------------------------------------ 夹具

def make_shop_catalog() -> Dict[str, Any]:
    """一份自洽的商店目录整包；引用全部包内可解析。"""
    return {
        "version": 1,
        "shops": [{"id": "shop-drill", "name": "演练店家"}],
        "series": [
            {
                "id": "series-drill",
                "shopID": "shop-drill",
                "name": "2026 秋冬",
                "year": 2026,
                "month": 9,
            }
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
        "variants": [
            {"id": "variant-drill", "productID": "product-drill", "color": "黑", "size": "M"}
        ],
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
        # 图片随包走：`local:` 引用必须能在归档的 images/ 里解析到真文件
        "assets": [
            {"id": "asset-drill", "type": "productImage", "originalURL": "local:img-DRILL.jpg"}
        ],
    }


def build_archive(work: Path, doc: Optional[Dict[str, Any]] = None) -> Path:
    """按 Mac 端「导出待发布整包」的布局打 tar：`shop-catalog.json` + `images/`。"""
    root = work / "tarroot"
    images = root / "images"
    images.mkdir(parents=True, exist_ok=True)
    (root / "shop-catalog.json").write_text(
        json.dumps(doc or make_shop_catalog(), ensure_ascii=False, indent=2), encoding="utf-8"
    )
    # 一张最小的 JPEG 头 + 尾巴：够 mimetypes 认出 .jpg，也够 sha256 有内容
    (images / "img-DRILL.jpg").write_bytes(b"\xff\xd8\xff\xe0drill-bridge-image-bytes\xff\xd9")
    archive = work / "export.tar"
    with tarfile.open(archive, "w") as tar:
        tar.add(str(root / "shop-catalog.json"), arcname="shop-catalog.json")
        tar.add(str(images / "img-DRILL.jpg"), arcname="images/img-DRILL.jpg")
    return archive


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


# ------------------------------------------------------------------ 主流程

def main() -> int:
    global VERBOSE, KEEP

    parser = argparse.ArgumentParser(description="运营桥接器离线演练")
    parser.add_argument("--verbose", action="store_true", help="打印每一步的完整事件流")
    parser.add_argument("--keep", action="store_true", help="保留工作目录以便排查")
    args = parser.parse_args()
    VERBOSE = args.verbose
    KEEP = args.keep

    if not BRIDGE.exists():
        print("❌ 找不到桥接器：{}".format(BRIDGE), file=sys.stderr)
        return 2

    work = Path(tempfile.mkdtemp(prefix="bridge_drill_"))
    print("运营桥接器 · 离线全链路演练")
    print("python : {}".format(sys.executable))
    print("桥接器 : {}".format(BRIDGE))
    print("工作区 : {}".format(work))

    try:
        section("准备夹具（自带；不依赖任何随 App 版本变动的资源目录）")
        (work / "input").mkdir(parents=True, exist_ok=True)
        (work / "live").mkdir(parents=True, exist_ok=True)
        archive = build_archive(work)
        payload = sha256_file(archive)
        print("  整包归档 : {}".format(archive.name))
        print("  待发布摘要: {}".format(payload[:12] + "…"))

        # ---------------------------------------------------------- 引用形态清点
        # 这一段是**纯函数自证**（不起子进程）：拉回说明原先写死「图片引用是
        # thmedia:<内容摘要>」—— 而线上可能存在不符的版本（2026-09-28 实测 dev
        # releaseSeq 1 的 560 个引用**全是 `local:`**，受控发布器的构建必然改写它们）。
        # 现在改成「实测出来再报」，所以清点本身的判定要有锁。
        section("阶段 0 · 图片引用形态清点（纯函数自证）")
        sys.path.insert(0, str(HERE))
        import ops_publish_bridge as bridge_module  # noqa: E402

        census = bridge_module._media_reference_census({
            "assets": [{"originalURL": "local:img-A.jpg",
                        "thumbnailURL": "thmedia:" + "a" * 64}],
            "series": [{"cover": "bundle:cover.png",
                        "priceChart": {"sourceImage": "local:img-A.jpg"}}],
            "shops": [{"logo": "https://example.com/x.png"}],
            "products": [{"note": "这句话不是引用"}],
        })
        check("同一文件被多处引用时逐处计数（local: = 2）",
              census.get("local:") == 2, "local: 数了两处", json.dumps(census))
        check("thmedia: / bundle: / http(s) 各自分桶",
              census.get("thmedia:") == 1 and census.get("bundle:") == 1
              and census.get("https://") == 1, "三个桶各 1", json.dumps(census))
        check("空目录也给结论（不写成空串）",
              bridge_module._census_text({}) == "没有任何图片引用",
              bridge_module._census_text({}))

        # ---------------------------------------------------------- 基线（R07）
        section("阶段 1 · R07 基线核对（只读，不写任何东西）")
        req_baseline = write_request(work / "req-baseline.json", work,
                                     payload_hash=payload, archive=archive)
        code, events, raw = run_bridge("baseline", req_baseline)
        step("空线上目录读基线", EXIT_OK, code, raw)
        check("只吐 NDJSON", not non_json_lines(events),
              "stdout 每一行都是 JSON 对象", "\n".join(non_json_lines(events)))
        baseline = next((e for e in events if e.get("type") == "baseline"), None)
        check("读到「尚无发布头」", baseline is not None and int(baseline.get("releaseSeq") or 0) == 0,
              "releaseSeq = 0（本次将是首次发布）", raw)
        check("基线核对不产生副作用", not (work / "live" / "THRelease.json").exists(),
              "live/ 下没有出现 THRelease.json")

        # ---------------------------------------------------------- pull-catalog（空线上）
        #
        # 放在发布之前：此时线上**还没有**发布头，正是要验「没有可拉回的目录」这一支
        # 是否如实说「线上是空的」，而不是把本地那份当成基线。
        section("阶段 1b · pull-catalog（线上还没有发布头）")
        req_pull_empty = write_request(work / "req-pull-empty.json", work,
                                      payload_hash=payload, archive=archive,
                                      request_id="drill-req-pull-empty")
        code, events, raw = run_bridge("pull-catalog", req_pull_empty)
        step("空线上拉回基线", EXIT_OK, code, raw)
        check("如实说「线上是空的」",
              "尚无商店发布头" in message_of(events) and "不是从线上来的" in message_of(events),
              "结论点名线上为空、本地内容非线上来源", message_of(events))
        check("空线上不产出目录文件",
              not (work / "release-seq7" / "shop-catalog.json").exists(),
              "没有 shop-catalog.json（没有内容就不编一份出来）")

        # ---------------------------------------------------------- 演练 dry-run
        section("阶段 2 · 演练（构建 + 校验 + 计划，但不写线上）")
        req_dry = write_request(work / "req-dry.json", work,
                                payload_hash=payload, archive=archive, dry_run=True,
                                request_id="drill-req-dry")
        code, events, raw = run_bridge("publish", req_dry)
        step("本机演练（dryRun）", EXIT_OK, code, raw)
        check("演练不留线上副作用", not (work / "live" / "THRelease.json").exists(),
              "live/ 下没有出现 THRelease.json")
        check("演练结论不是「已确认」",
              outcome_of(events) is None or outcome_of(events) != "confirmed",
              "结果事件里没有 outcome=confirmed（演练绝不代表已上线）", raw)
        check("阶段事件覆盖构建与复校验",
              {"build", "verifyArtifact"} <= {str(e.get("stage")) for e in events if e.get("type") == "stage"},
              "build / verifyArtifact 都出现过", raw)
        receipt_dry = json.loads((work / "receipt-seq7.json").read_text(encoding="utf-8"))
        check("回执带上任务归属",
              receipt_dry.get("requestID") == "drill-req-dry"
              and receipt_dry.get("jobID") == "drill-job-1"
              and receipt_dry.get("artifactDigest") == payload,
              "requestID / jobID / artifactDigest 已回填")

        # ---------------------------------------------------------- 真正发布（本地目录）
        section("阶段 3 · 发布到本机演练目录（filesystem，仍然不碰 CloudKit）")
        req_apply = write_request(work / "req-apply.json", work,
                                  payload_hash=payload, archive=archive,
                                  request_id="drill-req-apply")
        code, events, raw = run_bridge("publish", req_apply)
        step("发布 apply", EXIT_OK, code, raw)
        check("发布头已落地", (work / "live" / "THRelease.json").exists(),
              "live/THRelease.json 存在")
        check("图片随包上线（THMedia）", any((work / "live" / "THMedia").glob("*.jpg")),
              "THMedia/ 里有按内容摘要命名的文件")
        check("结论 = confirmed", outcome_of(events) == "confirmed",
              "outcome = confirmed（回读确认过）", raw)
        check("阶段事件覆盖七步里的切头与确认",
              {"switchHead", "confirmHead"} <=
              {str(e.get("stage")) for e in events if e.get("type") == "stage"},
              "switchHead / confirmHead 都出现过", raw)
        receipt = json.loads((work / "receipt-seq7.json").read_text(encoding="utf-8"))
        check("回执声明已回读确认", receipt.get("readBackConfirmed") is True,
              "readBackConfirmed = true")

        # ---------------------------------------------------------- R07 过期基线闸门
        #
        # 此时线上已经有 releaseSeq=7 + 一个确定的 rootIndexHash，可以真正比对了。
        # 这一节存在的理由：在此之前，桥接器**从不读** baseReleaseSeq /
        # baseRootIndexHash / baselineAcknowledged 三个字段 —— App 写进请求，接收方不看，
        # 于是「发布前检测过期基线」看起来做了、实际没做。
        section("阶段 3b · R07 过期基线闸门（这正是长期缺失的那一步）")
        online_seq = int(receipt.get("releaseSeq") or 0)
        online_hash = str(receipt.get("rootIndexHash") or "")
        print("  线上当前 : releaseSeq={} rootIndexHash={}…".format(
            online_seq, online_hash[:12]))

        # 3b.1 基线一致 + 未显式确认 → 应当放行（闸门不能误伤正确流程）
        req_ok = write_request(work / "req-base-ok.json", work, release_seq=81,
                               payload_hash=payload, archive=archive, dry_run=True,
                               request_id="drill-req-base-ok",
                               base_seq=online_seq, base_hash=online_hash,
                               baseline_ack=False)
        code, events, raw = run_bridge("publish", req_ok)
        step("基线一致则放行（未确认也放行）", EXIT_OK, code, raw)

        # 3b.2 发布号不一致 + 未确认 → 必须拒绝
        req_stale = write_request(work / "req-base-stale.json", work, release_seq=82,
                                  payload_hash=payload, archive=archive,
                                  request_id="drill-req-base-stale",
                                  base_seq=online_seq - 1, base_hash=online_hash,
                                  baseline_ack=False)
        code, events, raw = run_bridge("publish", req_stale)
        step("发布号过期被拒", EXIT_CONFLICT, code, raw)
        check("拒绝文案点名「基线已过期」并给出出路",
              "基线已过期" in message_of(events) and "拉回基线" in message_of(events),
              "结论含 R07 字样与处置指引", message_of(events))
        check("过期基线**没有**进入构建",
              not (work / "release-seq82").exists(),
              "没有产物目录（闸门在构建之前，不白跑几十兆图片）")

        # 3b.3 摘要不一致（发布号相同）+ 未确认 → 必须拒绝
        #      —— 这一条比发布号更强：别人发了「同一个号」时，只有摘要能发现。
        req_hash = write_request(work / "req-base-hash.json", work, release_seq=83,
                                 payload_hash=payload, archive=archive,
                                 request_id="drill-req-base-hash",
                                 base_seq=online_seq,
                                 base_hash="00" * 32,
                                 baseline_ack=False)
        code, events, raw = run_bridge("publish", req_hash)
        step("根清单摘要不一致被拒", EXIT_CONFLICT, code, raw)
        check("点名摘要不一致",
              "根清单摘要不一致" in message_of(events),
              "结论里说清是摘要不同（不是发布号）", message_of(events))

        # 3b.4 基线根本没回填 + 未确认 → 必须拒绝
        req_none = write_request(work / "req-base-none.json", work, release_seq=84,
                                 payload_hash=payload, archive=archive,
                                 request_id="drill-req-base-none",
                                 baseline_ack=False)
        code, events, raw = run_bridge("publish", req_none)
        step("基线未回填被拒", EXIT_CONFLICT, code, raw)

        # 3b.5 基线不一致但运营**显式确认** → R07 给的唯一出口，放行并留痕
        req_ack = write_request(work / "req-base-ack.json", work, release_seq=85,
                                payload_hash=payload, archive=archive, dry_run=True,
                                request_id="drill-req-base-ack",
                                base_seq=online_seq + 9, base_hash=online_hash,
                                baseline_ack=True)
        code, events, raw = run_bridge("publish", req_ack)
        step("显式确认后放行", EXIT_OK, code, raw)
        check("放行时把不一致项照实告警（不静默）",
              any(e.get("level") == "warning" and "基线不一致" in str(e.get("message"))
                  for e in events if e.get("type") == "log"),
              "有一条 warning 记录不一致项", raw)

        # ---------------------------------------------------------- pull-catalog（有内容）
        section("阶段 3c · pull-catalog（把线上商店目录拉回本地）")
        before_release_bytes = (work / "live" / "THRelease.json").read_bytes()
        req_pull = write_request(work / "req-pull.json", work, release_seq=90,
                                 payload_hash=payload, archive=archive,
                                 request_id="drill-req-pull")
        code, events, raw = run_bridge("pull-catalog", req_pull)
        step("拉回线上商店目录", EXIT_OK, code, raw)
        catalog_event = next((e for e in events if e.get("type") == "catalog"), None)
        catalog_path = Path(str((catalog_event or {}).get("path") or ""))
        check("产出 shop-catalog.json 且事件给出路径",
              catalog_event is not None and catalog_path.exists(),
              "catalog 事件带 path，文件真的在", raw)
        pull_manifest = {}
        manifest_path = work / "release-seq90" / "pull-manifest.json"
        if manifest_path.exists():
            pull_manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
        check("清单对齐线上发布头与载荷摘要",
              pull_manifest.get("releaseSeq") == online_seq
              and pull_manifest.get("rootIndexHash") == online_hash
              and str((catalog_event or {}).get("payloadHash") or "") != "",
              "releaseSeq / rootIndexHash 与线上一致，payloadHash 非空", raw)
        check("拉回内容与本地导入夹具同构（计数对得上）",
              isinstance(catalog_event, dict)
              and int((catalog_event.get("itemCounts") or {}).get("products", -1)) == 1
              and int((catalog_event.get("itemCounts") or {}).get("shops", -1)) == 1,
              "products=1 / shops=1（与夹具一致）",
              json.dumps(catalog_event or {}, ensure_ascii=False))
        check("拉回是**只读**：线上发布头逐字节未变",
              (work / "live" / "THRelease.json").read_bytes() == before_release_bytes,
              "live/THRelease.json 前后字节相同")
        # 引用形态必须是**实测出来的**，不能替数据下结论（见阶段 0 的说明）。
        # 本夹具经受控发布器构建，所以这里应当数到 thmedia:（不是写死的期望，是事实核对）。
        check("清单里带上实测的引用形态（mediaReferences）",
              isinstance(pull_manifest.get("mediaReferences"), dict)
              and int((pull_manifest.get("mediaReferences") or {}).get("thmedia:", 0)) >= 1,
              "mediaReferences.thmedia: ≥ 1（这份确实是受控发布器产物）",
              json.dumps(pull_manifest.get("mediaReferences"), ensure_ascii=False))

        # ---------------------------------------------------------- R09 查询
        section("阶段 4 · R09 结果查询（这是第一动作，不是重发）")
        code, events, raw = run_bridge("query", req_apply)
        step("查询结果", EXIT_OK, code, raw)
        check("查询得 confirmed", outcome_of(events) == "confirmed",
              "线上发布号 + 根清单摘要都与本次产物一致", raw)

        # ---------------------------------------------------------- 拒绝路径
        section("阶段 5 · 拒绝路径（每一条都必须给出可读结论，而不是 traceback）")

        # 5.1 摘要不符 = 请求冻结之后归档被改动过
        tampered = work / "export-tampered.tar"
        tampered.write_bytes(archive.read_bytes() + b"tampered")
        req_tamper = write_request(work / "req-tamper.json", work,
                                   payload_hash=payload, archive=tampered,
                                   release_seq=8, request_id="drill-req-tamper")
        code, events, raw = run_bridge("publish", req_tamper)
        step("归档被改动 → 摘要不符", EXIT_VALIDATION, code, raw)
        check("结论点名「摘要与请求不一致」", "摘要与请求不一致" in message_of(events),
              "message 里说清是摘要不符，而不是笼统失败", raw)

        # 5.2 环境与适配器错配：development 却写 filesystem
        req_mismatch = write_request(work / "req-mismatch.json", work,
                                     payload_hash=payload, archive=archive,
                                     environment="development", adapter="filesystem",
                                     release_seq=8, request_id="drill-req-mismatch")
        code, events, raw = run_bridge("publish", req_mismatch)
        step("development + filesystem 错配", EXIT_USAGE, code, raw)
        check("结论点名「环境/适配器」", "适配器" in message_of(events),
              "不静默降级成 filesystem", raw)

        # 5.3 协议版本不符
        req_version = write_request(work / "req-version.json", work,
                                    payload_hash=payload, archive=archive,
                                    schema_version=99, release_seq=8,
                                    request_id="drill-req-version")
        code, events, raw = run_bridge("publish", req_version)
        step("协议版本不符", EXIT_USAGE, code, raw)
        check("结论点名「协议版本不一致」", "协议版本不一致" in message_of(events),
              "提示更新 App，而不是解出半个请求", raw)

        # 5.4 缺必填字段
        req_missing = write_request(work / "req-missing.json", work,
                                    payload_hash=payload, archive=archive,
                                    release_seq=8, request_id="drill-req-missing",
                                    drop_fields=("payloadHash",))
        code, events, raw = run_bridge("publish", req_missing)
        step("缺必填字段 payloadHash", EXIT_USAGE, code, raw)
        check("结论点名缺哪个字段", "payloadHash" in message_of(events),
              "message 里带出字段名", raw)

        # 5.5 同号重发（线上已是 7）
        req_same = write_request(work / "req-same.json", work,
                                 payload_hash=payload, archive=archive,
                                 release_seq=7, request_id="drill-req-same")
        code, events, raw = run_bridge("publish", req_same)
        step("同一发布号重发 → 冲突", EXIT_CONFLICT, code, raw)
        check("结论 = 冲突类", outcome_of(events) in ("conflict", "refused"),
              "不许把重复发布号当成成功", raw)

        # 5.6 缺图必须硬失败（不能静默发一个没图的包）
        missing_doc = make_shop_catalog()
        missing_doc["assets"][0]["originalURL"] = "local:no-such-image.jpg"
        archive_missing = build_archive(work / "missing", missing_doc)
        req_missing_media = write_request(
            work / "req-missing-media.json", work,
            payload_hash=sha256_file(archive_missing), archive=archive_missing,
            release_seq=8, request_id="drill-req-missing-media")
        code, events, raw = run_bridge("publish", req_missing_media)
        step("缺图必须硬失败", EXIT_VALIDATION, code, raw)
        check("结论要求先修产物", "修产物" in message_of(events) or "构建失败" in message_of(events),
              "报告为「产物要修」，而不是可重试的网络失败", raw)

        # 5.7 R09 反面：线上没有发布头时查询 → 必须说「没有生效、可重试」，而不是「已确认」
        empty_root = work / "live-empty"
        empty_root.mkdir(parents=True, exist_ok=True)
        req_empty = write_request(work / "req-empty.json", work,
                                  payload_hash=payload, archive=archive,
                                  release_seq=9, request_id="drill-req-empty")
        request_json = json.loads(req_empty.read_text(encoding="utf-8"))
        request_json["filesystemRoot"] = str(empty_root)
        req_empty.write_text(json.dumps(request_json, ensure_ascii=False, indent=2),
                             encoding="utf-8")
        code, events, raw = run_bridge("query", req_empty)
        step("线上无发布头时查询", EXIT_OK, code, raw)
        check("结论 = 没有生效（不是 confirmed）", outcome_of(events) == "failed",
              "query 绝不把「没读到」当成「已确认」", raw)
        check("允许按原任务重试", result_event(events).get("retryable") is True,
              "retryable = true（切头前失败本来就该可重试）", raw)

        # ---------------------------------------------------------- 结果
        section("结果")
        print("  通过 {} 项，失败 {} 项".format(PASS, FAIL))
        if FAIL:
            print("")
            print("  未通过的步骤：")
            for name in FAILED:
                print("    - {}".format(name))
            return 1
        print("")
        print("  ✅ 桥接协议全链路演练通过：")
        print("     基线只读核对 → 演练无副作用 → 发布 → 回读确认 → 结果查询 → 七类拒绝路径")
        print("     说明：全程 filesystem 适配器 + localFixture 环境，未访问真实 CloudKit、不需要任何凭据。")
        return 0
    finally:
        if KEEP:
            print("")
            print("工作目录已保留：{}".format(work))
        else:
            import shutil

            shutil.rmtree(work, ignore_errors=True)


if __name__ == "__main__":
    raise SystemExit(main())
