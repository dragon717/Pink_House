#!/usr/bin/env python3
"""跨环境增量发布的离线回归，所有远端读取用夹具，发布子进程截断。"""

import argparse
import contextlib
import copy
import io
import json
import subprocess
import tempfile
import tarfile
import unittest
from pathlib import Path
from unittest.mock import patch

import ops_publish_bridge as bridge
from build_release import build_pack, build_shop_catalog_pack
from preserve_target_partitions import preserve_target_partitions
from protocol import canonical_entity_id, canonical_json_bytes, sha256_hex
from publish_cloudkit import revalidate


class PromotionTests(unittest.TestCase):
    def fixture(self, directory):
        brand = {"brandID": "shaonv-xinyuan", "sourceCoverage": "curatedSelection",
                 "coverageDescription": "运营目录", "sourceTimeZone": "Asia/Shanghai"}
        doc = {"version": 1, "shops": [{"id": "shop", "name": "合并后店家"}]}
        descriptor, data, _ = build_shop_catalog_pack(brand, doc,
            argparse.Namespace(coverage_mode="complete", checked_through="2026-10-11"))
        root = {"schemaVersion": 1, "releaseSeq": 7, "publishedAt": "2026-10-11T00:00:00Z",
                "revocationEpoch": 0, "brands": [brand], "partitions": [descriptor], "withdrawals": []}
        release = {"recordName": "th.release.catalog-v1", "schemaVersion": 1, "releaseSeq": 7,
                   "previousReleaseSeq": 6, "publishedAt": root["publishedAt"], "revocationEpoch": 0,
                   "minimumReaderVersion": 1, "rootIndexHash": sha256_hex(canonical_json_bytes(root)),
                   "encoding": "json-gzip", "partitionCount": 1, "recordCount": 1}
        (directory / "packs").mkdir()
        (directory / "audit").mkdir()
        (directory / "packs" / (descriptor["payloadHash"] + ".json.gz")).write_bytes(data)
        (directory / "root-index.json").write_bytes(canonical_json_bytes(root))
        (directory / "release.json").write_bytes(canonical_json_bytes(release))
        (directory / "audit/release-manifest.json").write_bytes(canonical_json_bytes({"media": []}))
        other_brand = dict(brand, brandID="other-brand", coverageDescription="线上独有时光馆内容")
        other, other_bytes, _ = build_pack(other_brand,
            {"commerceItems": [{"id": "original", "title": "线上画册商品"}]},
            "commerce-product", "complete", "2026-10-11", {}, "all")
        old_shop = copy.deepcopy(descriptor)
        old_shop["payloadHash"] = "a" * 64
        old_shop["packRecordName"] = "th.pack." + "a" * 64
        other["dependencyPackRecordNames"] = [old_shop["packRecordName"]]
        target = dict(root, releaseSeq=6, brands=[other_brand, brand], partitions=[other, old_shop],
                      revocationEpoch=3, withdrawals=[{"canonicalEntityID": canonical_entity_id("other-brand", "commerce-product", "withdrawn")}],
                      futureMetadata={"keep": True})
        target_bytes = canonical_json_bytes(target)
        head = {"releaseSeq": 6, "rootIndexHash": sha256_hex(target_bytes),
                "revocationEpoch": 3, "minimumReaderVersion": 1}

        class Reader:
            def fetch_root_index_bytes(self): return target_bytes
            def fetch_pack_bytes(self, digest):
                if digest != other["payloadHash"]: raise AssertionError("不得镜像旧商店整包")
                return other_bytes
            def media_exists_many(self, hashes): return set()

        return Reader(), head, target, other_bytes

    def testKeepsOtherPacksWithdrawalsMetadataAndVersionGates(self):
        with tempfile.TemporaryDirectory() as tmp:
            directory = Path(tmp)
            reader, head, target, data = self.fixture(directory)
            preserve_target_partitions(directory, reader, head)
            release, _, root, errors = revalidate(directory)
            self.assertEqual(errors, [])
            self.assertEqual(root["withdrawals"], target["withdrawals"])
            self.assertEqual(root["futureMetadata"], target["futureMetadata"])
            self.assertEqual(root["revocationEpoch"], 3)
            self.assertEqual(release["minimumReaderVersion"], 1)
            self.assertEqual(release["previousReleaseSeq"], 6)
            kept = next(p for p in root["partitions"] if p["entityType"] == "commerce-product")
            shop = next(p for p in root["partitions"] if p["entityType"] == "shop-catalog")
            self.assertEqual(kept["dependencyPackRecordNames"], [shop["packRecordName"]])
            self.assertEqual((directory / "packs" / (kept["payloadHash"] + ".json.gz")).read_bytes(), data)
            self.assertEqual(release["recordCount"], 2)
            self.assertEqual(release["partitionCount"], 2)

    def testChangedRootStopsBeforePublication(self):
        with tempfile.TemporaryDirectory() as tmp:
            directory = Path(tmp)
            reader, head, _, _ = self.fixture(directory)
            reader.fetch_root_index_bytes = lambda: b'{}'
            with self.assertRaisesRegex(Exception, "摘要已变化"):
                preserve_target_partitions(directory, reader, head)

    def testUnsupportedReaderGateCannotBeSilentlyLowered(self):
        with tempfile.TemporaryDirectory() as tmp:
            directory = Path(tmp)
            reader, head, _, _ = self.fixture(directory)
            head["minimumReaderVersion"] = 2
            with self.assertRaisesRegex(Exception, "minimumReaderVersion"):
                preserve_target_partitions(directory, reader, head)

    def testCorruptPreservedPackStopsPublication(self):
        with tempfile.TemporaryDirectory() as tmp:
            directory = Path(tmp)
            reader, head, _, _ = self.fixture(directory)
            reader.fetch_pack_bytes = lambda _: b'corrupt'
            with self.assertRaisesRegex(Exception, "分片摘要"):
                preserve_target_partitions(directory, reader, head)

    def testFirstPublicationKeepsBuiltArtifact(self):
        with tempfile.TemporaryDirectory() as tmp:
            directory = Path(tmp)
            reader, _, _, _ = self.fixture(directory)
            original = (directory / "root-index.json").read_bytes()
            reader.fetch_root_index_bytes = lambda: self.fail("空库没有可读根清单")
            preserve_target_partitions(directory, reader, None)
            self.assertEqual((directory / "root-index.json").read_bytes(), original)

    def run_bridge(self, directory, head, reader, stale=False, image=None, image_suffix="jpg"):
        doc = {"version": 1, "shops": [{"id": "shop", "name": "增量合并店家"}]}
        if image:
            digest = sha256_hex(image)
            doc["shops"][0]["logo"] = "thmedia:" + digest
        archive = directory / "release.tar"
        with tarfile.open(archive, 'w', format=tarfile.USTAR_FORMAT) as tar:
            def add(name, data):
                item = tarfile.TarInfo(name); item.size = len(data)
                tar.addfile(item, io.BytesIO(data))
            add("shop-catalog.json", canonical_json_bytes(doc))
            if image: add("images/" + digest + "." + image_suffix, image)
        request = {"requestID": "promotion", "jobID": "promotion", "draftID": "promotion",
                   "targetEnvironment": "production", "dryRun": False,
                   "archivePath": str(archive), "inputDirectory": str(directory / "input"),
                   "outputDirectory": str(directory / "output"), "receiptPath": str(directory / "receipt.json"),
                   "releaseSeq": 7 if head else 1, "baseReleaseSeq": 5 if stale else (6 if head else 0),
                   "baseRootIndexHash": head["rootIndexHash"] if head else None,
                   "payloadHash": sha256_hex(archive.read_bytes()), "preserveTargetPartitions": True}
        calls = []
        def child(argv, quiet):
            calls.append(Path(argv[1]).name)
            if calls[-1] == "build_release.py":
                result = subprocess.run(argv, capture_output=True, text=True, encoding="utf-8")
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                return result.returncode, []
            # 截断真实发布，核对交给原发布器的完整产物。
            release, _, root, errors = revalidate(directory / "output")
            self.assertEqual(errors, [])
            if head: self.assertEqual(len(root["partitions"]), 2)
            if image:
                media = json.loads((directory / "output/media.json").read_text(encoding="utf-8"))
                self.assertEqual(media["media"][0]["contentHash"], digest)
            return 1, []
        with patch.object(bridge, "read_head", return_value=head), \
             patch.object(bridge, "make_adapter", return_value=reader), \
             patch.object(bridge, "run_child", side_effect=child), \
             contextlib.redirect_stdout(io.StringIO()):
            bridge.run_publish(request, True)
        return calls

    def testBridgePreservesTargetBeforeHandingToExistingPublisher(self):
        with tempfile.TemporaryDirectory() as tmp:
            directory = Path(tmp)
            reader, head, _, _ = self.fixture(directory)
            self.assertEqual(self.run_bridge(directory, head, reader), ["build_release.py", "publish_cloudkit.py"])

    def testStaleTargetCannotReachBuildOrUpload(self):
        with tempfile.TemporaryDirectory() as tmp:
            directory = Path(tmp)
            reader, head, _, _ = self.fixture(directory)
            self.assertEqual(self.run_bridge(directory, head, reader, stale=True), [])

    def testSourceRemoteImageBecomesUploadableInEmptyTarget(self):
        with tempfile.TemporaryDirectory() as tmp:
            directory = Path(tmp)
            reader, _, _, _ = self.fixture(directory)
            self.assertEqual(self.run_bridge(directory, None, reader, image=b'\xff\xd8\xffsource-image'),
                             ["build_release.py", "publish_cloudkit.py"])

    def testJPEGAndUppercaseCacheSuffixesReachTheExistingPublisher(self):
        for suffix in ("jpeg", "JPG"):
            with self.subTest(suffix=suffix), tempfile.TemporaryDirectory() as tmp:
                directory = Path(tmp)
                reader, _, _, _ = self.fixture(directory)
                self.assertEqual(self.run_bridge(directory, None, reader,
                    image=b'\xff\xd8\xffcached-image', image_suffix=suffix),
                    ["build_release.py", "publish_cloudkit.py"])


if __name__ == "__main__":
    unittest.main(verbosity=2)
