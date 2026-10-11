#!/usr/bin/env python3
"""币种数据修复的离线回归；不使用凭证、不读写真实公共库。"""

import copy
import io
import json
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from protocol import ProtocolError, canonical_json_bytes, sha256_hex
from repair_operator_currencies import apply, assert_baseline, prepare, repair_catalog
from publish_adapters import CloudKitWebServicesAdapter, Credentials
from verify_publication import CloudKitPublicReader


class CurrencyRepairTests(unittest.TestCase):
    def testUnknownMissingAndEmptyCurrenciesAreFilledWithoutChangingMoney(self):
        source = {"products": [{"id": "p"}], "saleEvents": [
            {"id": "e1", "productID": "p", "price": 570, "deposit": 100, "balance": 470},
            {"id": "e2", "productID": "p", "price": 680, "currency": None},
            {"id": "e3", "productID": "p", "price": 690, "currency": "UNKNOWN"},
            {"id": "e4", "productID": "p", "price": 700, "currency": ""}]}
        before = copy.deepcopy(source)
        result, changes = repair_catalog(source)
        self.assertEqual(len(changes), 4)
        self.assertTrue(all(e["currency"] == "CNY" for e in result["saleEvents"]))
        for original, fixed in zip(source["saleEvents"], result["saleEvents"]):
            self.assertEqual({k: v for k, v in original.items() if k != "currency"},
                             {k: v for k, v in fixed.items() if k != "currency"})
        self.assertEqual(source, before)

    def testKnownCurrenciesImagesDeletionMarkersAndAllOtherFieldsArePreserved(self):
        source = {"products": [{"id": "p", "images": ["cover"], "category": "JSK"}],
                  "saleEvents": [{"id": "j", "productID": "p", "price": 24800, "currency": "JPY"},
                                 {"id": "c", "productID": "p", "price": 570, "currency": "CNY"}],
                  "assets": [{"id": "cover", "mediaKey": "a" * 64}],
                  "removedProductIDs": ["deleted"], "variants": [{"id": "color"}],
                  "styleProfiles": [{"id": "fabric"}], "futureField": {"value": 7}}
        result, changes = repair_catalog(source)
        self.assertEqual(changes, [])
        self.assertEqual(result, source)

    def testCorrectionOfCNYProductIsExplicitlyFilledAndNoEventIsInvented(self):
        source = {"products": [{"id": "p", "priceCorrection": {
            "reservationPrice": 570, "correctedAt": "2026-10-01T00:00:00Z"}}], "saleEvents": []}
        result, changes = repair_catalog(source)
        self.assertEqual(result["products"][0]["priceCorrection"]["currency"], "CNY")
        self.assertEqual(result["saleEvents"], [])
        self.assertEqual(changes[0]["field"], "products.priceCorrection.currency")

    def testNilCorrectionInheritingJPYDoesNotBecomeCNY(self):
        source = {"products": [{"id": "p", "priceCorrection": {"stockPrice": 25000}}],
                  "saleEvents": [{"id": "e", "productID": "p", "price": 24800, "currency": "JPY"}]}
        result, changes = repair_catalog(source)
        self.assertEqual(result, source)
        self.assertEqual(changes, [])

    def testSecondRepairIsIdempotent(self):
        fixed, _ = repair_catalog({"products": [], "saleEvents": [
            {"id": "e", "productID": "p", "price": 570, "currency": "UNKNOWN"}]})
        twice, changes = repair_catalog(fixed)
        self.assertEqual(twice, fixed)
        self.assertEqual(changes, [])

    def testStaleSeqHashAndChangeTagAreRejected(self):
        baseline = {"releaseSeq": 20, "rootIndexHash": "a", "changeTag": "t"}
        assert_baseline(baseline, baseline)
        for key, value in [("releaseSeq", 21), ("rootIndexHash", "b"), ("changeTag", "new")]:
            with self.subTest(key=key), self.assertRaises(ProtocolError):
                assert_baseline(dict(baseline, **{key: value}), baseline)
        with self.assertRaises(ProtocolError):
            assert_baseline(None, baseline)

    def testPrepareIsReadOnlyAndPreservesItsFrozenOutput(self):
        root = canonical_json_bytes({"partitions": []})
        head = {"releaseSeq": 20, "rootIndexHash": sha256_hex(root), "changeTag": "tag",
                "schemaVersion": 1, "minimumReaderVersion": 1}

        class Reader:
            def fetch_current_release(self):
                return head

            def fetch_root_index_bytes(self):
                return root

            def put_release(self, *args):
                raise AssertionError("prepare 不得写云端")

        with tempfile.TemporaryDirectory() as directory:
            out = Path(directory) / "冻结证据"
            with patch("repair_operator_currencies.make_adapter", return_value=Reader()) as factory:
                audit = prepare("development", out)
                self.assertEqual(audit["changes"], [])
                self.assertFalse(factory.call_args.args[2], "prepare 的 adapter 必须关闭写入")
                with self.assertRaises(ProtocolError):
                    prepare("development", out)

    def testModifiedArtifactsAreRejectedBeforeAnyCloudRequest(self):
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory)
            (output / "release").mkdir()
            (output / "release/root-index.json").write_text("modified", encoding="utf-8")
            (output / "audit.json").write_text(json.dumps({
                "environment": "development", "changes": [{"id": "e"}],
                "artifactHashes": {"root-index.json": "original"}}), encoding="utf-8")
            with patch("repair_operator_currencies.make_adapter") as factory:
                with self.assertRaises(ProtocolError):
                    apply("development", output)
                factory.assert_not_called()

    def testReaderReturnsOriginalProtocolAndMinimumClientVersions(self):
        adapter = CloudKitWebServicesAdapter(Credentials("test", "development", "unused", "unused"),
                                            apply=False)
        fields = {k: {"value": v} for k, v in {"releaseSeq": 20, "revocationEpoch": 2,
                  "rootIndexHash": "digest", "schemaVersion": 1, "minimumReaderVersion": 3,
                  "previousReleaseSeq": 19}.items()}
        with patch.object(adapter, "_send", return_value={"records": [
                {"recordName": "th.release.catalog-v1", "recordChangeTag": "tag", "fields": fields}]}):
            head = adapter.fetch_current_release()
        self.assertEqual(head["schemaVersion"], 1)
        self.assertEqual(head["minimumReaderVersion"], 3)
        self.assertEqual(head["previousReleaseSeq"], 19)

    def testIndependentVerifierUsesSharedHTTPSFailoverForRequestsAndAssets(self):
        reader = CloudKitPublicReader(Credentials("test", "development", "unused", "unused"))
        with patch("publish_adapters.sign_request", return_value="test-signature"), \
                patch("publish_adapters.open_https", side_effect=lambda *a, **k: io.BytesIO(b'{}')) as opener, \
                patch("urllib.request.urlopen", side_effect=AssertionError("不得绕过共用出网回退")):
            self.assertEqual(reader._post("records/lookup", {"records": []}), {})
            self.assertEqual(reader._download({"downloadURL": "https://example.test/asset"}), b'{}')
            self.assertEqual(opener.call_count, 2)


if __name__ == "__main__":
    unittest.main(verbosity=2)
