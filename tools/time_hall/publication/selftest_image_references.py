#!/usr/bin/env python3
"""全图片字段的发布回归：直接引用须上传，资源 ID 须保持，缺失引用须阻断。"""
import hashlib
import tempfile
import unittest
from pathlib import Path

from build_release import collect_shop_catalog_media
from protocol import ProtocolError, validate_shop_catalog_media


class ImageReferenceTests(unittest.TestCase):
    def test_direct_product_and_variant_media_are_collected_without_rewriting_asset_ids(self):
        payload = b'\x89PNG\r\n\x1a\nreference-enumeration-fixture'
        digest = hashlib.sha256(payload).hexdigest()
        doc = {"assets": [{"id": "asset-cover", "originalURL": "local:cover.png"}],
               "products": [{"id": "product", "images": ["asset-cover", "local:cover.png"]}],
               "variants": [{"id": "variant", "imageAssetID": "local:cover.png"}]}
        with tempfile.TemporaryDirectory() as tmp:
            directory = Path(tmp)
            (directory / 'cover.png').write_bytes(payload)
            rewritten, records, files = collect_shop_catalog_media(doc, directory)
        self.assertEqual(len(records), 1)
        self.assertEqual(len(files), 1)
        self.assertEqual(rewritten['products'][0]['images'], ['asset-cover', 'thmedia:' + digest])
        self.assertEqual(rewritten['variants'][0]['imageAssetID'], 'thmedia:' + digest)
        self.assertEqual(validate_shop_catalog_media(rewritten, {digest}), [])

    def test_missing_remote_and_dangling_asset_references_cannot_bypass_gate(self):
        doc = {"products": [{"id": "product", "images": ["asset-missing", "thmedia:" + 'a' * 64]}],
               "variants": [{"id": "variant", "imageAssetID": "local:missing.png"}]}
        issues = validate_shop_catalog_media(doc, set())
        self.assertEqual({issue['code'] for issue in issues},
                         {'media.asset.missing', 'media.reference.missing', 'media.reference.local'})
        with tempfile.TemporaryDirectory() as tmp:
            with self.assertRaises(ProtocolError):
                collect_shop_catalog_media(doc, Path(tmp))


if __name__ == '__main__':
    unittest.main()
