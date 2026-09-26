#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""运营工作台（PinkHouseOps）↔ 受控发布流水线的**机器可读桥接入口**。

对应文档：`docs/PinkHouse_千牛式上新方案_离线阅读.html` §5.2 / §6 / R07 / R08 / R09。

## 为什么需要它，而不是让 App 直接解析 CLI 的人类输出

`build_release.py` / `publish_cloudkit.py` 打印的是**给人看**的文本
（`[3/7] 上传缺失媒体（不可变，只增不改）`）。App 去正则匹配这些行，
任何一次文案调整都会让它静默失效 —— 而失效的表现是「界面停在『上传中』」，
看起来像网络问题。所以本文件把那些文本**在唯一一处**翻译成 NDJSON 事件，
App 只读 JSON。

## 它**不**做什么（硬约束）

* **不重写发布算法**。构建走 `build_release.py`，发布走 `publish_cloudkit.py`，
  全部以子进程调用，参数原样透传。这里没有第二份七步顺序。
* **不做授权判断**。来源是否 approved 由 `sources.yaml` 与那两个脚本决定；
  本文件只如实上报退出码。
* **不接收业务参数，只读一个请求文件**。命令行上只有 `--mode` 与 `--request`
  两个业务参数，所以不存在「App 拼出一条危险命令行」的可能。
* **不打印凭证**。凭证只由 `publish_adapters.Credentials.load` 从 Keychain /
  环境变量读，本文件从不接触。

## 请求文件

`--request <path>` 指向一份 `ShopCatalogPublishRequest` 的 JSON（字段名见
Swift 侧 `ShopCatalogPublishProtocol.swift`）。**App 写请求文件就是唯一的「提交」动作**。

## 事件流（stdout，NDJSON 一行一条，`sort_keys=True`）

    {"type":"hello","schemaVersion":1,...}
    {"type":"stage","stage":"build","state":"started","stepOrdinal":1,...}
    {"type":"log","level":"info","message":"..."}          ← 子进程原始输出行，原样透传
    {"type":"artifact","releaseSeq":7,"rootIndexHash":"...","payloadHash":"...","path":"..."}
    {"type":"baseline","releaseSeq":6,"rootIndexHash":"..."}
    {"type":"catalog","path":"...","releaseSeq":6,"rootIndexHash":"...","itemCounts":{...}}   ← pull-catalog
    {"type":"receipt","path":"...","releaseSeq":7,"rootIndexHash":"..."}
    {"type":"result","outcome":"confirmed","exitCode":0,...}

**结论只由「退出码 + 回执文件」推出**，不靠解析文案。阶段事件只用于进度展示：
即使所有 `[N/7]` 标记都没认出来（例如上游文案改了），最终结论依然正确 ——
这是刻意的设计，避免「文案改了 → 结论没了」。

## 退出码（与 `publish_cloudkit.py` 同一张表，另加 6）

    0 成功（含 dry-run）      2 用法/配置      3 校验未通过
    4 被拒绝（权限/环境/来源） 5 冲突           6 桥接器内部错误

## 用法

    # 只读线上发布头（R07 的基线核对）
    python3 ops_publish_bridge.py --mode baseline --request request.json

    # 提交（真正写线上）。构建之前会先比对基线，过期且未显式确认 → 拒绝（R07）
    python3 ops_publish_bridge.py --mode publish --request request.json

    # 结果待确认时先查询，禁止换号重发（R09）
    python3 ops_publish_bridge.py --mode query --request request.json

    # 只读拉回线上商店目录（建立本地基线）。产物写到请求的 outputDirectory：
    #   shop-catalog.json   目录本体（**已下发口径**：归档条目已剔除）
    #   pull-manifest.json  发布号 / 根清单摘要 / 载荷摘要 / 计数 / 说明
    python3 ops_publish_bridge.py --mode pull-catalog --request request.json
"""

from __future__ import annotations

import argparse
import datetime as dt
import gzip
import hashlib
import json
import re
import subprocess
import sys
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

from protocol import (  # noqa: E402
    SHOP_CATALOG_ALL_FIELDS,
    SHOP_CATALOG_ENTITY_TYPE,
    ProtocolError,
    sha256_hex,
)
from publish_adapters import (  # noqa: E402
    CredentialError,
    make_adapter,
)

# ------------------------------------------------------------------ 协议常量

PROTOCOL_SCHEMA_VERSION = 1

EXIT_OK = 0
EXIT_USAGE = 2
EXIT_VALIDATION = 3
EXIT_REFUSED = 4
EXIT_CONFLICT = 5
EXIT_INTERNAL = 6

MODE_BASELINE = "baseline"
MODE_PUBLISH = "publish"
MODE_QUERY = "query"
#: **只读**地把线上商店目录拉回本地（建立/刷新本地基线的内容）。
#: 与 publish 是两条完全不同的路径：它连 dry-run 的「写」都不需要，
#: 因为它**只有读**。见 `run_pull_catalog`。
MODE_PULL_CATALOG = "pull-catalog"

#: `publish_cloudkit.py` 的七步行首标记 → 协议里的阶段名。
#: **只在这里出现一次**，App 不解析这些文字。
STEP_TO_STAGE = {
    1: "verifyArtifact",
    2: "readHead",
    3: "uploadMedia",
    4: "uploadPacks",
    5: "readBack",
    6: "switchHead",
    7: "confirmHead",
}

STEP_LINE_RE = re.compile(r"^\[(\d)/7\]\s*(.*)$")

#: 「已进入第 6 步」的判定。切头之前失败 = 线上还是旧版（可安全重试）；
#: 切头之后（含切头那一刻）失败 = **结果不明**（必须先查询，禁止重发）—— R09。
HEAD_SWITCH_STEP = 6


# ------------------------------------------------------------------ 输出

def emit(payload: Dict[str, Any]) -> None:
    """往 stdout 写一条 NDJSON 事件。"""
    payload.setdefault("at", _now_iso())
    print(json.dumps(payload, ensure_ascii=False, sort_keys=True), flush=True)


def _now_iso() -> str:
    return dt.datetime.now(dt.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def log_line(level: str, message: str) -> None:
    emit({"type": "log", "level": level, "message": message.rstrip()})


def stage(stage_name: str, state: str, message: Optional[str] = None) -> None:
    payload: Dict[str, Any] = {"type": "stage", "stage": stage_name, "state": state}
    if message:
        payload["message"] = message
    emit(payload)


# ------------------------------------------------------------------ 参数

def parse_args(argv: Optional[List[str]] = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="运营工作台 ↔ 受控发布流水线的 NDJSON 桥接入口"
    )
    parser.add_argument(
        "--mode",
        required=True,
        choices=(MODE_BASELINE, MODE_PUBLISH, MODE_QUERY, MODE_PULL_CATALOG),
        help="baseline=只读线上发布头；publish=构建并发布；query=结果待确认时查询；"
             "pull-catalog=只读拉回线上商店目录（建立本地基线）",
    )
    parser.add_argument("--request", required=True, type=Path, help="冻结请求 JSON")
    parser.add_argument(
        "--quiet",
        action="store_true",
        help="不透传子进程的原始输出行（只发阶段与结论事件）",
    )
    return parser.parse_args(argv)


# ------------------------------------------------------------------ 请求

def load_request(path: Path) -> Dict[str, Any]:
    if not path.exists():
        raise ProtocolError("请求文件不存在：{}".format(path))
    try:
        request = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise ProtocolError("请求文件无法解析：{}".format(error)) from error
    if not isinstance(request, dict):
        raise ProtocolError("请求文件不是 JSON 对象")
    version = request.get("schemaVersion")
    if version != PROTOCOL_SCHEMA_VERSION:
        raise ProtocolError(
            "协议版本不一致：请求为 {!r}，桥接器为 {}。请更新 App。".format(
                version, PROTOCOL_SCHEMA_VERSION
            )
        )
    for key in (
        "requestID",
        "jobID",
        "draftID",
        "targetEnvironment",
        "releaseSeq",
        "inputDirectory",
        "archivePath",
        "outputDirectory",
        "receiptPath",
        "payloadHash",
    ):
        if request.get(key) in (None, ""):
            raise ProtocolError("请求缺少必填字段 {}".format(key))
    return request


def adapter_name(request: Dict[str, Any]) -> str:
    """适配器只由环境推导，**请求里那个字段仅作交叉校验**。

    为什么不让请求直接指定适配器：环境与适配器一旦可以分别指定，
    就存在「development + filesystem」这类组合 —— 运营以为在发开发环境，
    实际只写了个本地目录。这类错配的代价是「以为发出去了」。
    """
    environment = str(request["targetEnvironment"])
    expected = "filesystem" if environment == "localFixture" else "cloudkit"
    declared = request.get("adapter") or expected
    if declared != expected:
        raise ProtocolError(
            "环境 {!r} 必须使用适配器 {!r}，请求里写的是 {!r}".format(
                environment, expected, declared
            )
        )
    return expected


def ck_environment(request: Dict[str, Any]) -> str:
    """`--environment` 只接受 development / production；localFixture 走 filesystem。"""
    environment = str(request["targetEnvironment"])
    return "development" if environment == "localFixture" else environment


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


# ------------------------------------------------------------------ 子进程

def run_child(argv: List[str], quiet: bool) -> Tuple[int, List[int]]:
    """跑一个既有脚本，把它的输出逐行翻译成 log 事件（与阶段标记）。

    阶段事件的产出规则：看到第 N 步的标记时，先给**上一步**发 `succeeded`，
    再给第 N 步发 `started`。**最后一步留给调用方收尾**（成功还是失败只有
    退出码知道），否则「一直在开始、从不结束」的阶段会在界面上永远转圈。
    """
    stages_seen: List[int] = []
    process = subprocess.Popen(
        argv,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        encoding="utf-8",
        errors="replace",
        bufsize=1,
    )
    assert process.stdout is not None
    for raw in process.stdout:
        line = raw.rstrip()
        if not line:
            continue
        marker = STEP_LINE_RE.match(line.strip())
        if marker:
            step = int(marker.group(1))
            if stages_seen:
                stage(STEP_TO_STAGE[stages_seen[-1]], "succeeded")
            stages_seen.append(step)
            stage(STEP_TO_STAGE[step], "started", marker.group(2))
            continue
        if not quiet:
            log_line("info", line)
    exit_code = process.wait()
    return exit_code, stages_seen


# ------------------------------------------------------------------ 线上发布头

def read_head(request: Dict[str, Any]) -> Optional[Dict[str, Any]]:
    """只读线上发布头（不发任何写请求）。

    用的是**受控发布器自己的适配器**（`publish_adapters.make_adapter`），
    所以「什么是线上当前版本」只有一处口径。`apply=False` 保证任何情况下都不写。
    """
    name = adapter_name(request)
    filesystem_root = None
    if name == "filesystem":
        raw_root = request.get("filesystemRoot")
        if not raw_root:
            raise ProtocolError("localFixture 环境需要请求里给出 filesystemRoot")
        filesystem_root = Path(str(raw_root))
    adapter = make_adapter(
        name, ck_environment(request), False, False, filesystem_root
    )
    return adapter.fetch_current_release()


def baseline_mismatches(request: Dict[str, Any], head: Optional[Dict[str, Any]]) -> List[str]:
    """R07：草稿记录的线上基线**是否与真实线上一致**。返回不一致的条目（空 = 一致）。

    ## 为什么必须有这个函数（而不是「反正发布号会递增」）

    `build_release.py` 只从**本地**已批准来源构建，**从不读线上**。所以产物里那份
    完整 ShopCatalog 就是本地输入的副本 —— 拿一份旧导出去发布，会把线上后来的
    改动**整块覆盖**。原来唯一的事实性保护是 `publish_cloudkit.py` 的
    「本地发布号不大于线上则拒绝」，而它只在你选的号**恰好撞车**时才生效
    （选 online+5 就完全不拦）。实测确认：桥接器此前**从不读**
    `baseReleaseSeq` / `baseRootIndexHash` / `baselineAcknowledged` 三个字段 ——
    App 把它们写进请求，接收方不看。那正是「看起来做了、实际没做」。

    ## 判定规则

    | 草稿基线 | 线上 | 结论 |
    |---|---|---|
    | 空 | 有 | 不一致：无法证明这份内容基于线上当前版本 |
    | 有 | 无发布头 | 不一致：草稿基于某个版本，线上却什么都没有 |
    | 发布号不同 | — | 不一致 |
    | 摘要不同 | — | 不一致（**这是比发布号更强的那一条**） |
    | 摘要读不到 | — | 不一致：拿不到证据就不能当一致（只比发布号会漏判） |
    | 全一致 | — | 一致 |

    `baselineAcknowledged` 是 R07 给的**唯一出口**（运营显式确认「我知道线上变了，
    仍按这个基线发」）。它不当成「检查通过」，只当成「已留痕的例外」——
    调用方必须把不一致项原样告警出来，不能静默。
    """
    problems: List[str] = []
    base_seq = request.get("baseReleaseSeq")
    base_hash = request.get("baseRootIndexHash")
    has_base = base_seq not in (None, "") or bool(base_hash)

    if not has_base:
        return [
            "草稿没有回填线上基线（baseReleaseSeq 与 baseRootIndexHash 都是空）——"
            "无法证明这份内容是基于线上当前版本编辑的"
        ]

    if not head:
        return [
            "线上尚无商店发布头（看起来是首次发布），但草稿记录的基线是 "
            "releaseSeq={} / 摘要={}".format(base_seq, _short_hash(base_hash))
        ]

    online_seq = int(head.get("releaseSeq") or 0)
    online_hash = head.get("rootIndexHash")

    if base_seq not in (None, "") and int(base_seq) != online_seq:
        problems.append("发布号不一致：草稿基线 {} / 线上 {}".format(base_seq, online_seq))
    if not base_hash:
        problems.append("草稿没有记录基线摘要（baseRootIndexHash 为空），只比了发布号")
    elif not isinstance(online_hash, str) or not online_hash:
        # 读不到摘要 ≠ 一致。只比发布号会把「别人发了同一个号」误判成一致，
        # 所以这里算**不一致**，让运营显式确认或先修读取链路。
        problems.append("线上读不到根清单摘要，无法与草稿基线摘要比对（只比发布号不足以判定）")
    elif str(base_hash) != online_hash:
        problems.append(
            "根清单摘要不一致：草稿基线 {} / 线上 {}".format(
                _short_hash(base_hash), _short_hash(online_hash)
            )
        )
    return problems


def _short_hash(value: Any) -> str:
    if isinstance(value, str) and len(value) > 12:
        return value[:12] + "…"
    return str(value)


def head_payload(request: Dict[str, Any], head: Optional[Dict[str, Any]]) -> Dict[str, Any]:
    if not head:
        return {
            "type": "baseline",
            "releaseSeq": 0,
            "message": "线上尚无商店发布头（本次将是首次发布）",
        }
    release_seq = head.get("releaseSeq")
    payload: Dict[str, Any] = {
        "type": "baseline",
        "releaseSeq": int(release_seq) if release_seq is not None else 0,
    }
    root_hash = head.get("rootIndexHash")
    if isinstance(root_hash, str) and root_hash:
        payload["rootIndexHash"] = root_hash
    else:
        # 摘要读不到是**正常情况**（filesystem 之外不保证回吐该字段）。
        # 明确说出来，App 才好把「只比了发布号」讲清楚。
        payload["message"] = "已读到线上发布号，但没读到根清单摘要（本轮只比发布号）"
    return payload


# ------------------------------------------------------------------ 回执

def enrich_receipt(request: Dict[str, Any], release: Dict[str, Any]) -> Dict[str, Any]:
    """把任务归属与回读结论补进回执。

    `publish_cloudkit.py --receipt` 已经把公共库语义的字段写好了；这里**只加不删**，
    因为「这份回执是谁的、有没有回读确认过」是 App 才能回答的问题，
    而回执是 App 判断发布是否成立的唯一依据。
    """
    receipt_path = Path(str(request["receiptPath"]))
    receipt: Dict[str, Any] = {}
    if receipt_path.exists():
        try:
            loaded = json.loads(receipt_path.read_text(encoding="utf-8"))
            if isinstance(loaded, dict):
                receipt = loaded
        except (OSError, json.JSONDecodeError):
            # 回执坏了不能静默扔掉：它是唯一成功凭据。留痕并继续补字段。
            log_line("warning", "回执文件无法解析，已按空回执继续补字段：{}".format(receipt_path))
    receipt["requestID"] = request["requestID"]
    receipt["jobID"] = request["jobID"]
    receipt["draftID"] = request["draftID"]
    receipt["draftRevision"] = request.get("draftRevision")
    receipt["artifactDigest"] = request.get("payloadHash")
    receipt["verifiedAt"] = _now_iso()
    if release:
        receipt.setdefault("releaseSeq", release.get("releaseSeq"))
        receipt.setdefault("rootIndexHash", release.get("rootIndexHash"))
        receipt.setdefault("revocationEpoch", release.get("revocationEpoch"))
    receipt["readBackConfirmed"] = bool(receipt.get("applied")) and _head_matches_release(
        request, release
    )
    return receipt


def _head_matches_release(request: Dict[str, Any], release: Dict[str, Any]) -> bool:
    """回读确认：线上发布头是否就是本次产物。

    **两个一起比**（发布号 + 根清单摘要）：只比发布号会把「别人发了同一个号」
    误判成自己成功。摘要读不到时明确降级成「只比发布号」，并且回执里
    `readBackConfirmed` 仍然照实算 —— 不假装。
    """
    if not release:
        return False
    try:
        head = read_head(request)
    except (ProtocolError, CredentialError):
        return False
    if not head:
        return False
    if int(head.get("releaseSeq") or -1) != int(release.get("releaseSeq") or -2):
        return False
    local_hash = str(release.get("rootIndexHash") or "")
    online_hash = str(head.get("rootIndexHash") or "")
    if local_hash and online_hash:
        return local_hash == online_hash
    return True


def write_receipt(request: Dict[str, Any], receipt: Dict[str, Any]) -> None:
    receipt_path = Path(str(request["receiptPath"]))
    receipt_path.parent.mkdir(parents=True, exist_ok=True)
    receipt_path.write_text(
        json.dumps(receipt, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )


def load_release_artifact(output_directory: Path) -> Dict[str, Any]:
    release_path = output_directory / "release.json"
    if not release_path.exists():
        return {}
    try:
        loaded = json.loads(release_path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return {}
    return loaded if isinstance(loaded, dict) else {}


# ------------------------------------------------------------------ 结论

def outcome_result(
    outcome: str,
    exit_code: int,
    message: str,
    release: Optional[Dict[str, Any]] = None,
    retryable: bool = False,
) -> Dict[str, Any]:
    payload: Dict[str, Any] = {
        "type": "result",
        "outcome": outcome,
        "exitCode": int(exit_code),
        "message": message,
        "retryable": bool(retryable),
    }
    if release:
        if release.get("releaseSeq") is not None:
            payload["releaseSeq"] = int(release.get("releaseSeq"))
        if release.get("rootIndexHash"):
            payload["rootIndexHash"] = str(release.get("rootIndexHash"))
    return payload


def classify_publish_failure(
    exit_code: int, steps_seen: List[int], applied: bool
) -> Tuple[str, bool, str]:
    """把「子进程退出码 + 走到第几步 + 有没有真的写入」翻成结论。

    这张表是 R09 的核心，**不能靠猜**：

      · 走到第 7 步（确认发布头）却失败 → 发布头**可能已经切换**，
        查询之前不能重试 → `pendingConfirmation`；
      · 走到第 6 步（条件更新）抛错 → 适配器明确拒绝写入（changeTag 冲突
        或发布号不递增）→ `conflict`；
      · 第 6 步之前失败 → 线上仍是旧版本 → 可安全重试 → `failed`。

    `applied` 必须传进来：dry-run 下子进程**照样**打印 `[6/7]` / `[7/7]`
    标记，但它一个字节都没写。只看标记会把每一次演练失败都说成「结果不明」，
    那就把这个提示本身教成了噪音。
    """
    reached_switch = applied and HEAD_SWITCH_STEP in steps_seen
    reached_confirm = applied and 7 in steps_seen

    if exit_code == EXIT_CONFLICT:
        if reached_confirm:
            return (
                "pendingConfirmation",
                False,
                "已执行到「回读确认发布头」但仍未确认：**结果不明**，"
                "请先运行结果查询，不要直接重发（R09）。",
            )
        if reached_switch:
            return (
                "conflict",
                False,
                "切换发布头被拒（changeTag 冲突或发布号未递增），线上仍是旧版本。"
                "需要重新读取线上版本、合并对方改动后再确认。",
            )
        return (
            "conflict",
            False,
            "发布被冲突检查中止（线上资源摘要不符或发布号不递增），线上仍是旧版本。",
        )
    if exit_code in (EXIT_USAGE, EXIT_VALIDATION, EXIT_REFUSED):
        return (
            "refused",
            False,
            "产物或环境不满足发布条件（退出码 {}）。重试不会改变结果，请先修配置。".format(
                exit_code
            ),
        )
    if reached_switch or reached_confirm:
        return (
            "pendingConfirmation",
            False,
            "在切换发布头之后失败（退出码 {}）：**结果不明**，先查询再决定。".format(exit_code),
        )
    return (
        "failed",
        True,
        "在切换发布头之前失败（退出码 {}），线上仍是旧版本，可以安全重试。".format(exit_code),
    )


# ------------------------------------------------------------------ 各模式

def run_baseline(request: Dict[str, Any], quiet: bool) -> int:
    stage("baseline", "started")
    try:
        head = read_head(request)
    except (ProtocolError, CredentialError) as error:
        stage("baseline", "failed")
        emit(outcome_result("refused", EXIT_REFUSED, "读线上发布头失败：{}".format(error)))
        return EXIT_REFUSED
    stage("baseline", "succeeded")
    emit(head_payload(request, head))
    return EXIT_OK


def run_query(request: Dict[str, Any], quiet: bool) -> int:
    """结果待确认时的查询：**这是 R09 要求的第一动作**，不是重新发布。"""
    stage("baseline", "started")
    try:
        head = read_head(request)
    except (ProtocolError, CredentialError) as error:
        stage("baseline", "failed")
        emit(outcome_result(
            "pendingConfirmation",
            EXIT_REFUSED,
            "查询失败，**结果仍然不明**：{}。请先解决读取问题，不要换号重发。".format(error),
        ))
        return EXIT_REFUSED
    stage("baseline", "succeeded")
    emit(head_payload(request, head))

    wanted_seq = int(request["releaseSeq"])
    online_seq = int(head.get("releaseSeq") or 0) if head else 0

    receipt = {}
    receipt_path = Path(str(request["receiptPath"]))
    if receipt_path.exists():
        try:
            loaded = json.loads(receipt_path.read_text(encoding="utf-8"))
            if isinstance(loaded, dict):
                receipt = loaded
        except (OSError, json.JSONDecodeError):
            receipt = {}

    if not head:
        emit(outcome_result(
            "failed",
            EXIT_OK,
            "线上没有发布头，本次发布**没有生效**。线上仍是旧版本，可以按原任务重试。",
            retryable=True,
        ))
        return EXIT_OK

    if online_seq == wanted_seq:
        local_hash = str(receipt.get("rootIndexHash") or "")
        online_hash = str(head.get("rootIndexHash") or "")
        if local_hash and online_hash and local_hash != online_hash:
            emit(outcome_result(
                "conflict",
                EXIT_OK,
                "线上发布号与本次相同（{}）但根清单摘要不同 —— 可能是别人发了同一个号。"
                "请先人工核对，不要回写旧版本。".format(online_seq),
            ))
            return EXIT_OK
        evidence = "发布号 + 根清单摘要" if (local_hash and online_hash) else "仅发布号（回执或线上缺摘要）"
        emit(outcome_result(
            "confirmed",
            EXIT_OK,
            "线上发布头已是本次产物（比对依据：{}）。注意这只代表发布头已生效，"
            "不代表每台离线设备都已刷新。".format(evidence),
        ))
        return EXIT_OK

    if online_seq > wanted_seq:
        emit(outcome_result(
            "replaced",
            EXIT_OK,
            "线上发布号（{}）已经高于本次（{}），本次产物已被取代。**不要**回写旧版本。".format(
                online_seq, wanted_seq
            ),
        ))
        return EXIT_OK

    emit(outcome_result(
        "failed",
        EXIT_OK,
        "线上发布号（{}）仍低于本次（{}），说明本次没有生效。线上仍是旧版本，"
        "可以按原任务重试。".format(online_seq, wanted_seq),
    ))
    return EXIT_OK


def find_shop_catalog_partitions(root_index: Any) -> List[Dict[str, Any]]:
    """从根清单里挑出商店目录分片（`entityType == "shop-catalog"`）。

    不按 `partitionID` 硬编码去猜：分片 ID 是 `partition_id(brandID, type, scope)` 算出来的，
    换品牌/换 scope 就会变。按**类型**挑才稳。
    """
    if not isinstance(root_index, dict):
        return []
    partitions = root_index.get("partitions")
    if not isinstance(partitions, list):
        return []
    return [
        item for item in partitions
        if isinstance(item, dict) and str(item.get("entityType")) == SHOP_CATALOG_ENTITY_TYPE
    ]


def run_pull_catalog(request: Dict[str, Any], quiet: bool) -> int:
    """**只读**回读线上商店目录整包，落成一份本地 JSON（建立/刷新本地基线）。

    ## 为什么必须有这条模式（2026-09-27 查出的事实）

    方案 §5 要求本地草稿 = **「当前线上完整基线」+ 变更集**。但在这条模式出现之前：
      · App 的入口只有「导入目录 JSON」，记的基线只有 `baseReleaseSeq` +
        `baseRootIndexHash` —— **是号码，不是内容**；
      · `build_release.py` 只从本地 `sources.yaml` 构建、**从不读线上**。
    于是「我导入的这份是不是线上当前内容」只能靠人工假设，而假设错了就会
    **整块覆盖**线上后来的改动（R07 要防的正是这个）。

    ## 三件说清楚才写成代码的事

    1. **绝不写线上**：全程 `apply=False` 适配器 + 只读方法（`fetch_*_bytes`）。
    2. ⚠️ **拿到的是「已下发口径」，不等于你本地那份**。构建时
       `strip_archived_shop_catalog` 已剔除归档条目、并剔除了孤儿销售事件，
       图片引用也已被改写成 `thmedia:<内容摘要>`。所以拉回来的目录里：
       **不会有归档过的店家/系列/商品**，图片也不再是 `local:` 文件名。
       这不是丢数据，是「下发给用户的东西」的定义 —— 但必须**显式告知**。
    3. **摘要自证**：根清单字节的 SHA-256 必须等于发布头的 `rootIndexHash`；
       分片字节的 SHA-256 必须等于其 `payloadHash`。不符即中止（与
       `mirror_environments.py` 同一套约束），绝不在拿不到证据时降级。
    """
    output_directory = Path(str(request["outputDirectory"]))
    name = adapter_name(request)

    stage("baseline", "started", "回读线上发布头")
    try:
        head = read_head(request)
    except (ProtocolError, CredentialError) as error:
        stage("baseline", "failed")
        emit(outcome_result(
            "refused", EXIT_REFUSED, "读线上发布头失败，无法拉回基线：{}".format(error)))
        return EXIT_REFUSED
    stage("baseline", "succeeded")
    emit(head_payload(request, head))

    if not head:
        # 线上没有发布头 = 线上基线**确实是空的**。这是事实，不是失败：
        # 本地应当据此知道「我手上这份不是从线上来的」。
        emit(outcome_result(
            "confirmed",
            EXIT_OK,
            "线上尚无商店发布头：没有可拉回的目录。这说明线上现在是空的 —— "
            "**本地已有内容不是从线上来的**（首次发布才合理）。",
        ))
        return EXIT_OK

    online_seq = int(head.get("releaseSeq") or 0)
    root_index_hash = head.get("rootIndexHash")
    if not isinstance(root_index_hash, str) or not root_index_hash:
        emit(outcome_result(
            "refused",
            EXIT_REFUSED,
            "线上发布头读不到根清单摘要（rootIndexHash），无法定位并自证根清单，已中止 ——"
            "拿不到证据就不拉，避免把一份来源不明的目录当基线。",
        ))
        return EXIT_REFUSED

    filesystem_root = (
        Path(str(request["filesystemRoot"])) if name == "filesystem" else None
    )
    adapter = make_adapter(name, ck_environment(request), False, False, filesystem_root)

    root_bytes = adapter.fetch_root_index_bytes()
    if root_bytes is None:
        emit(outcome_result(
            "refused", EXIT_REFUSED, "取不到根清单资产字节，已中止（不猜、不降级）。"))
        return EXIT_REFUSED
    actual_root_hash = sha256_hex(root_bytes)
    if actual_root_hash != root_index_hash:
        emit(outcome_result(
            "refused",
            EXIT_REFUSED,
            "根清单摘要与发布头不一致（发布头 {} / 实际 {}）：已中止。".format(
                _short_hash(root_index_hash), _short_hash(actual_root_hash)
            ),
        ))
        return EXIT_REFUSED

    try:
        root_index = json.loads(root_bytes.decode("utf-8"))
    except (ValueError, UnicodeDecodeError) as error:
        emit(outcome_result(
            "refused", EXIT_VALIDATION, "根清单不是合法 JSON：{}".format(error)))
        return EXIT_VALIDATION

    partitions = find_shop_catalog_partitions(root_index)
    if not partitions:
        emit(outcome_result(
            "confirmed",
            EXIT_OK,
            "线上 releaseSeq={} 里**没有**商店目录分片（这一版只有其他时光馆内容）——"
            "线上商店基线因此为空目录，本地那份不是从线上来的。".format(online_seq),
        ))
        return EXIT_OK

    # 只认唯一一个：商店目录按设计是**整包一个分片**（不按实体拆包，见 protocol.py）。
    # 出现多个说明口径被改过，此时静默取第一个会拿到半份目录 —— 宁可中止。
    if len(partitions) > 1:
        emit(outcome_result(
            "refused",
            EXIT_REFUSED,
            "根清单里有 {} 个商店目录分片（按设计应当只有 1 个）：口径已变，"
            "已中止以免只拉回半份目录。".format(len(partitions)),
        ))
        return EXIT_REFUSED

    partition = partitions[0]
    payload_hash = str(partition.get("payloadHash") or "")
    if not payload_hash:
        emit(outcome_result(
            "refused", EXIT_REFUSED, "分片描述里没有 payloadHash，无法自证摘要，已中止。"))
        return EXIT_REFUSED

    pack_bytes = adapter.fetch_pack_bytes(payload_hash)
    if pack_bytes is None:
        emit(outcome_result(
            "refused", EXIT_REFUSED, "取不到数据包字节：{}，已中止。".format(payload_hash[:12])))
        return EXIT_REFUSED
    actual_pack_hash = sha256_hex(pack_bytes)
    if actual_pack_hash != payload_hash:
        emit(outcome_result(
            "refused",
            EXIT_REFUSED,
            "数据包摘要不符（期望 {} / 实际 {}）：已中止，不采信这份字节。".format(
                _short_hash(payload_hash), _short_hash(actual_pack_hash)
            ),
        ))
        return EXIT_REFUSED

    try:
        payload = json.loads(gzip.decompress(pack_bytes).decode("utf-8"))
    except (OSError, ValueError, UnicodeDecodeError) as error:
        emit(outcome_result(
            "refused", EXIT_VALIDATION, "数据包无法解压/解析：{}".format(error)))
        return EXIT_VALIDATION

    doc = payload.get("shopCatalog") if isinstance(payload, dict) else None
    if not isinstance(doc, dict):
        emit(outcome_result(
            "refused", EXIT_VALIDATION, "数据包里没有 shopCatalog 载荷，已中止。"))
        return EXIT_VALIDATION

    counts: Dict[str, int] = {}
    for field in SHOP_CATALOG_ALL_FIELDS:
        value = doc.get(field)
        if isinstance(value, list):
            counts[field] = len(value)

    output_directory.mkdir(parents=True, exist_ok=True)
    catalog_path = output_directory / "shop-catalog.json"
    catalog_path.write_text(
        json.dumps(doc, ensure_ascii=False, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    manifest = {
        "pulledAt": _now_iso(),
        "targetEnvironment": str(request["targetEnvironment"]),
        "releaseSeq": online_seq,
        "rootIndexHash": root_index_hash,
        "payloadHash": payload_hash,
        "partitionID": partition.get("partitionID"),
        "coverageStatus": partition.get("coverageStatus"),
        "publishedAt": head.get("publishedAt"),
        "itemCounts": counts,
        "note": (
            "这是**已下发口径**：归档条目与孤儿销售事件在构建时已被剔除，"
            "图片引用是 thmedia:<内容摘要>（不是 local: 文件名）。"
        ),
    }
    (output_directory / "pull-manifest.json").write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )

    emit({
        "type": "catalog",
        "path": str(catalog_path),
        "releaseSeq": online_seq,
        "rootIndexHash": root_index_hash,
        "payloadHash": payload_hash,
        "itemCounts": counts,
    })
    log_line("info", "归档条目不会回来：线上分片是「已下发口径」，归档过的店家/系列/商品已被构建剔除；"
                     "图片引用是 thmedia:<内容摘要>，本地没有对应文件。")
    emit(outcome_result(
        "confirmed",
        EXIT_OK,
        "已把线上商店目录拉回本地（releaseSeq {}，店家 {} / 系列 {} / 商品 {}）。"
        "这是**已下发口径** —— 归档条目不在其中，图片是 thmedia: 引用。"
        "接下来把它作为本地基线导入，再在此基础上编辑。".format(
            online_seq,
            counts.get("shops", 0),
            counts.get("series", 0),
            counts.get("products", 0),
        ),
        release={"releaseSeq": online_seq, "rootIndexHash": root_index_hash},
    ))
    return EXIT_OK


def run_publish(request: Dict[str, Any], quiet: bool) -> int:
    environment = str(request["targetEnvironment"])
    dry_run = bool(request.get("dryRun"))
    archive_path = Path(str(request["archivePath"]))
    input_directory = Path(str(request["inputDirectory"]))
    output_directory = Path(str(request["outputDirectory"]))
    receipt_path = Path(str(request["receiptPath"]))
    release_seq = int(request["releaseSeq"])
    name = adapter_name(request)

    # ---------------- 冻结：请求文件就是冻结快照，App 侧已完成
    stage("freeze", "succeeded", "已收到冻结请求（草稿快照在 App 侧生成）")

    # ---------------- 请求完整性：产物摘要必须与请求一致
    if not archive_path.exists():
        emit(outcome_result(
            "refused", EXIT_VALIDATION, "待发布整包不存在：{}".format(archive_path)))
        return EXIT_VALIDATION
    actual_digest = sha256_file(archive_path)
    if str(request["payloadHash"]) != actual_digest:
        emit(outcome_result(
            "refused",
            EXIT_VALIDATION,
            "待发布整包的摘要与请求不一致（请求 {} / 实际 {}）："
            "说明请求冻结之后文件被改动过，已中止。".format(
                str(request["payloadHash"])[:12], actual_digest[:12]
            ),
        ))
        return EXIT_VALIDATION

    # ---------------- 基线闸门（R07）：**必须在构建之前**
    #
    # 两件事按这个顺序想清楚了才写：
    #   1. 放在构建之前，是因为基线过期时构建纯属白跑（几十兆图片 + 几分钟），
    #      而且更早失败给出的结论更干净（「先拉回基线」而不是「产物构建完了但被拒」）。
    #   2. **dry-run 也走同一判定**。演练如果放行、真跑被拒，就是本项目反复吃亏的
    #      「演练绿灯 ≠ 真路径正确」。演练的价值恰恰在于把真跑的判定提前演一遍。
    stage("baseline", "started", "比对线上基线（R07 过期检测）")
    try:
        head = read_head(request)
    except (ProtocolError, CredentialError) as error:
        stage("baseline", "failed")
        emit(outcome_result(
            "refused",
            EXIT_REFUSED,
            "读线上基线失败，因此**无法确认**这份草稿是不是基于线上当前内容：{}。"
            "已中止 —— 宁可挡住，也不拿一份不知道基于哪一版的完整包去覆盖线上。".format(error),
        ))
        return EXIT_REFUSED

    mismatches = baseline_mismatches(request, head)
    if mismatches and not bool(request.get("baselineAcknowledged")):
        stage("baseline", "failed", "基线已过期")
        emit(outcome_result(
            "refused",
            EXIT_CONFLICT,
            "**基线已过期**（R07）：本地草稿记录的线上版本与实际线上不一致，已中止。\n"
            + "".join("\n  · {}".format(item) for item in mismatches)
            + "\n线上当前 releaseSeq={}。请先「读取线上基线」回填，或先「从线上拉回基线」"
            "重建本地内容再编辑。\n"
            "确实要强行按这份基线发布（会覆盖线上后来出现的改动）时，才勾选"
            "「已知线上已变，仍按本基线发布」—— 该确认会写进请求文件留痕。".format(
                (head or {}).get("releaseSeq") or 0
            ),
        ))
        return EXIT_CONFLICT

    if mismatches:
        # `baselineAcknowledged` 不是「检查通过」，只是「已留痕的例外」——
        # 所以照实告警，不静默。
        stage("baseline", "succeeded", "基线不一致，但运营已显式确认继续")
        for item in mismatches:
            log_line("warning", "基线不一致（运营已显式确认继续）：{}".format(item))
    else:
        stage("baseline", "succeeded")
        emit(head_payload(request, head))

    input_directory.mkdir(parents=True, exist_ok=True)
    receipt_path.parent.mkdir(parents=True, exist_ok=True)
    if output_directory.exists():
        # 只清「看起来就是发布产物」的目录（与 build_release 同一判据），
        # 避免把运营自己的东西删掉。
        looks_like_release = (output_directory / "release.json").exists() or (
            output_directory / "root-index.json"
        ).exists()
        is_empty = not any(output_directory.iterdir())
        if not (looks_like_release or is_empty):
            emit(outcome_result(
                "refused",
                EXIT_VALIDATION,
                "产物目录 {} 已存在且不像发布产物目录，已中止（不替运营删东西）。".format(
                    output_directory
                ),
            ))
            return EXIT_VALIDATION

    # ---------------- 构建（第 1 步的一半）
    stage("build", "started", "构建不可变产物")
    build_argv = [
        sys.executable,
        str(HERE / "build_release.py"),
        "--input",
        str(input_directory),
        "--shop-catalog-archive",
        str(archive_path),
        "--output",
        str(output_directory),
        "--release-seq",
        str(release_seq),
    ]
    build_code, build_steps = run_child(build_argv, quiet)
    if build_code != 0:
        stage("build", "failed")
        # 构建阶段失败一律算「本地产物问题」：它发生在任何远端写入之前，
        # 所以既不是可重试的网络失败，也不是冲突 —— 是产物要修。
        emit(outcome_result(
            "refused",
            EXIT_VALIDATION,
            "构建产物失败（build_release.py 退出码 {}）。线上未做任何改动；"
            "请按上面的日志修产物后重试。".format(build_code),
        ))
        return EXIT_VALIDATION
    release = load_release_artifact(output_directory)
    stage("build", "succeeded")
    emit({
        "type": "artifact",
        "releaseSeq": release.get("releaseSeq"),
        "rootIndexHash": release.get("rootIndexHash"),
        "payloadHash": actual_digest,
        "path": str(output_directory),
    })
    # 第 1 步的另一半（复校验）在 publish_cloudkit 里跑；这里先把 build 之后的
    # 「产物已就绪」标出来，让阶段事件与七步顺序保持一致。
    stage("verifyArtifact", "succeeded", "产物已构建（复校验由发布器第 1 步再做一次）")

    # ---------------- 发布（第 2–7 步，含第 1 步复校验）
    publish_argv = [
        sys.executable,
        str(HERE / "publish_cloudkit.py"),
        "--release",
        str(output_directory),
        "--adapter",
        name,
        "--environment",
        ck_environment(request),
        "--receipt",
        str(receipt_path),
    ]
    if name == "filesystem":
        publish_argv += ["--filesystem-root", str(request["filesystemRoot"])]
    if dry_run:
        publish_argv += ["--dry-run"]
    else:
        publish_argv += ["--apply"]

    code, steps = run_child(publish_argv, quiet)
    # 最后一步的收尾：成功还是失败只有退出码知道（见 run_child 的说明）。
    if steps:
        stage(STEP_TO_STAGE[steps[-1]], "succeeded" if code == 0 else "failed")

    receipt = enrich_receipt(request, release)
    write_receipt(request, receipt)
    emit({
        "type": "receipt",
        "path": str(receipt_path),
        "releaseSeq": receipt.get("releaseSeq"),
        "rootIndexHash": receipt.get("rootIndexHash"),
    })

    if code == 0:
        if dry_run:
            log_line("info", "演练完成：未写入任何内容（线上没有改变）。")
            return EXIT_OK
        confirmed = bool(receipt.get("readBackConfirmed"))
        emit(outcome_result(
            "confirmed" if confirmed else "pendingConfirmation",
            EXIT_OK,
            "发布头已切换并回读确认（releaseSeq {}）。这不代表每台离线设备都已刷新。".format(
                release.get("releaseSeq")
            ) if confirmed else
            "发布命令成功返回，但**没有拿到回读确认**：请运行结果查询后再下结论。",
            release,
        ))
        return EXIT_OK

    outcome, retryable, message = classify_publish_failure(code, steps, not dry_run)
    emit(outcome_result(outcome, code, message, None, retryable))
    return code


# ------------------------------------------------------------------ 入口

def main(argv: Optional[List[str]] = None) -> int:
    args = parse_args(argv)
    emit({
        "type": "hello",
        "schemaVersion": PROTOCOL_SCHEMA_VERSION,
        "message": "已连接受控发布桥接器（协议 v{}）".format(PROTOCOL_SCHEMA_VERSION),
    })
    try:
        request = load_request(args.request)
    except ProtocolError as error:
        emit(outcome_result("refused", EXIT_USAGE, str(error)))
        return EXIT_USAGE

    try:
        if args.mode == MODE_BASELINE:
            return run_baseline(request, args.quiet)
        if args.mode == MODE_QUERY:
            return run_query(request, args.quiet)
        if args.mode == MODE_PULL_CATALOG:
            return run_pull_catalog(request, args.quiet)
        return run_publish(request, args.quiet)
    except ProtocolError as error:
        emit(outcome_result("refused", EXIT_USAGE, str(error)))
        return EXIT_USAGE
    except CredentialError as error:
        emit(outcome_result(
            "refused",
            EXIT_REFUSED,
            "发布凭证不可用：{}。请按 docs/TIME_HALL_CLOUDKIT_CONSOLE_SETUP.md 配置后重试。".format(error),
        ))
        return EXIT_REFUSED
    except Exception as error:  # noqa: BLE001 - 桥接器必须给出可读结论，不能只吐 traceback
        emit(outcome_result(
            "pendingConfirmation" if args.mode == MODE_PUBLISH else "refused",
            EXIT_INTERNAL,
            "桥接器内部错误：{}: {}".format(type(error).__name__, error),
        ))
        return EXIT_INTERNAL


if __name__ == "__main__":
    raise SystemExit(main())
