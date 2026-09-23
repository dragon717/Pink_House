#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
稳定来源 → 目标身份映射（第三版收口 §7.3「先补映射，不先换 ID」）。

解决问题（方案 R04）：
    旧脚本的 `unique_id()` 在候选 ID 冲突时自动追加 `-2/-3`，`next_id()` 用全局
    顺序号。二者都依赖**本次运行内的状态**——重跑、扩大范围或改变输入顺序就会
    让同一个来源实体拿到不同的目标 ID，进而产生重复商品、ID 漂移和跨快照冲突。
    顺序号 `-2/-3` 只能让「单次数组内 ID 看起来不重复」，它不是业务幂等策略。

这里的策略：
    1. 目标 ID 由「来源命名空间 + 来源实体类型 + 来源稳定 ID」**确定性**推导，
       不含任何运行序号；
    2. 映射写入 `migration-map.json` 并跨运行复用：
       同一来源再次出现 → 目标 ID 不变（no-op 或更新，绝不改名再新增）；
    3. 冲突（不同来源撞到同一个目标 ID）不静默改名，而是登记 `conflicts`
       交由人工确认——重名只是候选匹配，不是合并依据。

产物格式（每条映射）：
    {
      "namespace": "timehall" | "midsummer",
      "sourceType": "shop" | "series" | "product" | "variant" | "event" | "asset",
      "sourceID": "<来源稳定 ID>",
      "sourceContext": {"shopID": ..., "seriesID": ...},   # 同码跨店判定用
      "targetType": "shops" | "series" | ...,
      "targetID": "...",
      "rule": "<转换规则名>",
      "ruleVersion": "<规则版本>",
      "result": "created" | "reused" | "updated" | "split" | "skipped" | "conflict",
      "detail": "<补充说明，如拆分来源>"
    }
"""

import hashlib
import json
import os
import re

RULE_VERSION = "v3.1"

# 目标 ID 前缀（与仓库既有种子一致：`th-*` 已对用户暴露，不得改名）
PREFIX_BY_NAMESPACE = {
    "timehall": "th",
    "midsummer": "ms",
}

# 店家前缀沿用既有脚本口径，保证重跑映射到种子里已有的 shop id
SHOP_PREFIX_BY_NAMESPACE = {
    "timehall": "shop-th",
    "midsummer": "shop",
}


def slug(text, limit=60):
    """稳定 slug：只保留 [a-z0-9._-]，其余归一为 '-'。

    与旧 `sanitize_shop_id` 的差别：新旧口径必须**完全一致**，否则重跑时
    店家 ID 会漂移，导致「同一店家变成两个」。这里逐字沿用旧规则。
    """
    raw = (text or "").strip().lower()
    raw = re.sub(r"^https?://", "", raw)
    raw = re.sub(r"^www\.", "", raw)
    out = re.sub(r"[^a-z0-9]+", "-", raw).strip("-")
    return (out or "unknown")[:limit]


def stable_hash(text, length=12):
    """内容寻址后缀：同一输入永远同一输出，不含运行序号。"""
    return hashlib.sha1(text.encode("utf-8")).hexdigest()[:length]


def shop_target_id(namespace, merchant_id):
    """店家目标 ID。timehall → shop-th-<slug>；midsummer → shop-<slug>。"""
    prefix = SHOP_PREFIX_BY_NAMESPACE.get(namespace, "shop")
    return "{}-{}".format(prefix, slug(merchant_id))


def entity_target_id(namespace, source_id, prefix=None):
    """通用实体目标 ID：`<ns>-<稳定来源 ID>`。

    来源 ID 本身已稳定（productCode / catalogue id / item id）时直接使用，
    保证与仓库既有 `th-*` ID 完全一致；来源 ID 含分隔符时先 slug 化。
    """
    ns = PREFIX_BY_NAMESPACE.get(namespace, namespace)
    raw = str(source_id or "unknown").strip()
    if re.fullmatch(r"[A-Za-z0-9._-]+", raw):
        return "{}-{}".format(ns, raw)
    # slug 会把纯非 ASCII（如「テストページ」）整体清成 "unknown"，
    # 于是多条真实商品坍缩到同一个目标 ID。退化到内容寻址保证「不同来源 ≠ 同一条」。
    s = slug(raw)
    if s in ("", "unknown"):
        s = "x" + stable_hash(raw, 12)
    return "{}-{}".format(ns, s)


def child_target_id(namespace, parent_target_id, kind, *parts, prefix=None):
    """子实体（variant / event / asset）目标 ID。

    旧口径用全局顺序号 `var-th-00001`，重跑即漂移。这里改成
    「父目标 ID + 语义成分」的内容寻址：成分相同 → ID 相同（幂等追加），
    成分不同 → 一定是不同实体（不会因为顺序号错位而覆盖另一条）。
    """
    ns = PREFIX_BY_NAMESPACE.get(namespace, namespace)
    rendered = "|".join("" if p is None else str(p) for p in parts)
    return "{}-{}-{}-{}".format(
        ns, kind, stable_hash(parent_target_id), stable_hash(rendered, 10)
    )


class IdentityMap:
    """来源 → 目标映射表（可持久化，跨运行复用）。"""

    def __init__(self, path=None):
        self.path = path
        self.entries = []          # 本轮全部映射记录
        self._by_source = {}       # (namespace, sourceType, sourceID) -> entry
        self._taken = {}           # targetType -> {targetID: entry}
        self.conflicts = []
        if path and os.path.exists(path):
            self.load(path)

    @staticmethod
    def _key(namespace, source_type, source_id, source_context=None):
        """身份键必须带**来源上下文**（§7.3）。

        只按 sourceID 判等会把「A 店的 SC-001」与「B 店的 SC-001」认成同一条，
        从而静默合并两个不同商品。店家 / 系列上下文参与判等后，跨店同码会走到
        「候选目标 ID 冲突」分支，交由人工确认，而不是自动合并或自动改名。
        """
        ctx = ""
        if source_context:
            ctx = json.dumps(source_context, sort_keys=True, ensure_ascii=False)
        return (namespace, source_type, str(source_id), ctx)

    # ---- 持久化 --------------------------------------------------------
    def load(self, path=None):
        path = path or self.path
        if not path or not os.path.exists(path):
            return
        with open(path, "r", encoding="utf-8") as f:
            data = json.load(f)
        for e in data.get("entries", []) or []:
            self._by_source[self._key(e["namespace"], e["sourceType"], e["sourceID"],
                                      e.get("sourceContext"))] = e
            self._taken.setdefault(e["targetType"], {})[e["targetID"]] = e
        # 历史映射同样占位，防止本轮新增撞上历史目标 ID 后被静默改写
        self.entries = list(data.get("entries", []) or [])

    def save(self, path=None):
        path = path or self.path
        if not path:
            return
        os.makedirs(os.path.dirname(os.path.abspath(path)), exist_ok=True)
        payload = {
            "ruleVersion": RULE_VERSION,
            "totals": self.totals(),
            "conflicts": self.conflicts,
            "entries": self.entries,
        }
        with open(path, "w", encoding="utf-8") as f:
            json.dump(payload, f, ensure_ascii=False, indent=2, sort_keys=True)

    def totals(self):
        out = {}
        for e in self.entries:
            out[e["result"]] = out.get(e["result"], 0) + 1
        return out

    # ---- 查询 / 登记 ----------------------------------------------------
    def existing_target(self, namespace, source_type, source_id, source_context=None):
        """已登记过 → 返回原目标 ID（重放 no-op，绝不改名）。"""
        e = self._by_source.get(self._key(namespace, source_type, source_id, source_context))
        return e["targetID"] if e else None

    def existing_target_any_context(self, namespace, source_type, source_id):
        """忽略来源上下文查目标 ID（跨 scope 合并时用）。

        同一来源 ID 在不同上下文（画册条目 / 在售清单、不同系列）下会登记成多条
        映射，但它们解析出的目标 ID 是同一个。合并分支拿不到完整上下文时用它，
        避免因为少传一个上下文字段就查不到、进而写出悬空外键。
        """
        for e in reversed(self.entries):
            if (e.get("namespace") == namespace
                    and e.get("sourceType") == source_type
                    and e.get("sourceID") == source_id):
                return e["targetID"]
        return None

    def resolve(
        self,
        namespace,
        source_type,
        source_id,
        target_type,
        candidate,
        rule,
        source_context=None,
        result=None,
        detail=None,
    ):
        """登记（或复用）一条映射。

        已存在同一来源 → 原样返回历史目标 ID，result 记为 reused；
        候选 ID 已被**别的来源**占用 → 登记 conflict 并保留候选（不自动 -2/-3）。
        """
        key = self._key(namespace, source_type, source_id, source_context)
        if key in self._by_source:
            prev = self._by_source[key]
            prev["result"] = result or "reused"
            if detail:
                prev["detail"] = detail
            return prev["targetID"]

        taken = self._taken.setdefault(target_type, {})
        occupant = taken.get(candidate)
        if occupant is not None and self._key(
                occupant.get("namespace"), occupant.get("sourceType"),
                occupant.get("sourceID"), occupant.get("sourceContext")) != key:
            # 不同来源撞同一目标 ID：这是需要人工判断的候选冲突，不是自动改名的地方
            self.conflicts.append({
                "namespace": namespace,
                "sourceType": source_type,
                "sourceID": source_id,
                "targetType": target_type,
                "targetID": candidate,
                "occupiedBy": {
                    "namespace": occupant.get("namespace"),
                    "sourceType": occupant.get("sourceType"),
                    "sourceID": occupant.get("sourceID"),
                },
                "reason": "不同来源实体解析到同一目标 ID（需人工确认是合并还是改名）",
            })

        entry = {
            "namespace": namespace,
            "sourceType": source_type,
            "sourceID": source_id,
            "sourceContext": source_context or {},
            "targetType": target_type,
            "targetID": candidate,
            "rule": rule,
            "ruleVersion": RULE_VERSION,
            "result": result or "created",
            "detail": detail,
        }
        self.entries.append(entry)
        self._by_source[key] = entry
        taken[candidate] = entry
        return candidate

    def mark(self, namespace, source_type, source_id, result, detail=None,
             source_context=None):
        """只更新某条映射的处理结果（跳过 / 冲突 / 待补等）。"""
        key = self._key(namespace, source_type, source_id, source_context)
        e = self._by_source.get(key)
        if e:
            e["result"] = result
            if detail:
                e["detail"] = detail

    def targets(self, target_type):
        return sorted(self._taken.get(target_type, {}).keys())

    def entries_by_result(self, result):
        return [e for e in self.entries if e.get("result") == result]
