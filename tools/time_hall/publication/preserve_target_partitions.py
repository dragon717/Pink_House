"""商店增量发布保留目标环境其他分片与撤回记录，只经只读适配器取回。"""

import json
from pathlib import Path

from protocol import (ProtocolError, SHOP_CATALOG_ENTITY_TYPE, canonical_json_bytes,
                      sha256_hex)
from publish_cloudkit import revalidate


def preserve_target_partitions(directory: Path, adapter, head):
    if not head:
        return
    root_bytes = adapter.fetch_root_index_bytes()
    if not root_bytes or sha256_hex(root_bytes) != head.get("rootIndexHash"):
        raise ProtocolError("线上根清单摘要已变化，请重新读取增量同步预览")
    target = json.loads(root_bytes.decode("utf-8"))
    if target.get("releaseSeq") != head.get("releaseSeq"):
        raise ProtocolError("线上根清单发布号与已读取基线不一致")
    built = json.loads((directory / "root-index.json").read_text(encoding="utf-8"))
    release = json.loads((directory / "release.json").read_text(encoding="utf-8"))
    shops = [p for p in built["partitions"] if p.get("entityType") == SHOP_CATALOG_ENTITY_TYPE]
    if len(shops) != 1:
        raise ProtocolError("增量同步必须构建唯一商店目录分片")
    old_shops = [p for p in target["partitions"] if p.get("entityType") == SHOP_CATALOG_ENTITY_TYPE]
    if len(old_shops) > 1:
        raise ProtocolError("线上存在多个商店目录分片，不能自动合并")
    replacements = {p["packRecordName"]: shops[0]["packRecordName"] for p in old_shops}
    kept = []
    for descriptor in target["partitions"]:
        if descriptor.get("entityType") == SHOP_CATALOG_ENTITY_TYPE:
            continue
        digest = descriptor["payloadHash"]
        data = adapter.fetch_pack_bytes(digest)
        if not data or sha256_hex(data) != digest:
            raise ProtocolError("线上保留分片摘要校验失败：" + descriptor["partitionID"])
        (directory / "packs" / (digest + ".json.gz")).write_bytes(data)
        descriptor = dict(descriptor)
        descriptor["dependencyPackRecordNames"] = [replacements.get(name, name)
            for name in descriptor.get("dependencyPackRecordNames", [])]
        kept.append(descriptor)
    # 从目标根清单开始，完整保留撤回、品牌范围及未知元数据。
    root = dict(target, releaseSeq=built["releaseSeq"], publishedAt=built["publishedAt"],
                partitions=kept + shops)
    brands = {b["brandID"]: b for b in target.get("brands", [])}
    for brand in built.get("brands", []):
        if any(p.get("brandID") == brand["brandID"] for p in shops):
            brands.setdefault(brand["brandID"], brand)
    root["brands"] = list(brands.values())
    root["revocationEpoch"] = max(target.get("revocationEpoch", 0), head.get("revocationEpoch", 0),
                                  built.get("revocationEpoch", 0))
    root_bytes = canonical_json_bytes(root)
    release.update(rootIndexHash=sha256_hex(root_bytes), revocationEpoch=root["revocationEpoch"],
                   minimumReaderVersion=max(release["minimumReaderVersion"],
                                            head.get("minimumReaderVersion", 1)),
                   brands=list(brands), partitionCount=len(root["partitions"]),
                   recordCount=sum(p["recordCount"] for p in root["partitions"]))
    (directory / "root-index.json").write_bytes(root_bytes)
    (directory / "release.json").write_bytes(canonical_json_bytes(release) + b"\n")
    _, _, _, errors = revalidate(directory)
    if errors:
        raise ProtocolError("保留线上分片后的产物校验失败：" + "; ".join(errors[:10]))
    audit_path = directory / "audit" / "release-manifest.json"
    audit = json.loads(audit_path.read_text(encoding="utf-8"))
    audit.update(rootIndexHash=release["rootIndexHash"], revocationEpoch=root["revocationEpoch"],
                 partitions=root["partitions"], withdrawals=root.get("withdrawals", []),
                 preservedTargetRootIndexHash=head["rootIndexHash"])
    audit_path.write_bytes(canonical_json_bytes(audit) + b"\n")
    checksums = [release["rootIndexHash"] + "  root-index.json"]
    checksums += [p["payloadHash"] + "  packs/" + p["payloadHash"] + ".json.gz"
                  for p in root["partitions"]]
    checksums += [m["contentHash"] + "  media/" + m["fileName"] for m in audit.get("media", [])]
    (directory / "audit" / "checksums.txt").write_text("\n".join(checksums) + "\n", encoding="utf-8")
