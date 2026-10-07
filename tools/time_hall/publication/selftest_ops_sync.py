#!/usr/bin/env python3
"""同步故障回归：部分下载可接收，错误不能伪装成不存在。全程离线。"""
import contextlib
import hashlib
import io
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

import ops_publish_bridge as bridge
from build_release import collect_shop_catalog_media
from protocol import ProtocolError
from publish_adapters import CloudKitWebServicesAdapter, Credentials, NetworkError, existing_records


class SyncTests(unittest.TestCase):
    def test_only_not_found_is_absent(self):
        self.assertEqual(existing_records({"records": [{"serverErrorCode": "NOT_FOUND"}]}), [])
        for response in ({}, {"records": []}, {"records": [{}]}, {"serverErrorCode": "ACCESS_DENIED"},
                         {"records": [{"serverErrorCode": "ACCESS_DENIED"}]}):
            with self.assertRaises(ProtocolError):
                existing_records(response)
        with self.assertRaises(NetworkError):
            existing_records({"records": [{"serverErrorCode": "THROTTLED"}]})

    def adapter(self, response):
        adapter = CloudKitWebServicesAdapter(
            Credentials("iCloud.test", "development", "test", "test"),
            apply=False, http_post=lambda *args: response)
        adapter._headers = lambda *args: {}
        return adapter

    def test_existing_media_without_asset_is_error(self):
        adapter = self.adapter({"records": [{"recordName": "th.media.test", "fields": {}}]})
        with self.assertRaises(ProtocolError):
            adapter.fetch_media_bytes("test")
        adapter = self.adapter({"records": [{"serverErrorCode": "NOT_FOUND"}]})
        self.assertIsNone(adapter.fetch_media_bytes("test"))

    def test_existing_head_without_sequence_is_error(self):
        adapter = self.adapter({"records": [{"recordName": "th.release.catalog-v1", "fields": {}}]})
        with self.assertRaises(ProtocolError):
            adapter.fetch_current_release()

    def test_batch_lookup_does_not_silently_drop_permission_error(self):
        adapter = self.adapter({"records": [{"recordName": "th.media.a"},
                                            {"serverErrorCode": "ACCESS_DENIED"}]})
        with self.assertRaises(ProtocolError):
            adapter.media_exists_many(["a", "b"])

    def test_cached_remote_image_can_be_uploaded_to_missing_target(self):
        payload = b'\xff\xd8\xffcached-image'
        digest = hashlib.sha256(payload).hexdigest()
        doc = {"assets": [{"id": "asset", "mediaKey": digest, "originalURL": "thmedia:" + digest}]}
        with tempfile.TemporaryDirectory() as tmp:
            directory = Path(tmp)
            (directory / (digest + '.jpg')).write_bytes(payload)
            rewritten, records, files = collect_shop_catalog_media(doc, directory)
            self.assertEqual(len(records), 1)
            self.assertEqual(records[0]['contentHash'], digest)
            self.assertEqual(len(files), 1)
            self.assertEqual(rewritten['assets'][0]['originalURL'], "thmedia:" + digest)
            (directory / (digest + '.jpg')).write_bytes(b'corrupt')
            with self.assertRaises(ProtocolError):
                collect_shop_catalog_media(doc, directory)

    def test_remote_reference_without_cache_still_needs_remote_proof(self):
        digest = 'a' * 64
        doc = {"assets": [{"id": "asset", "mediaKey": digest, "originalURL": "thmedia:" + digest}]}
        with tempfile.TemporaryDirectory() as tmp:
            rewritten, records, files = collect_shop_catalog_media(doc, Path(tmp))
            self.assertEqual(records, [])
            self.assertEqual(files, [])
            self.assertEqual(rewritten, doc)

    def test_empty_environment_returns_mergeable_catalog(self):
        with tempfile.TemporaryDirectory() as tmp:
            request = {"targetEnvironment": "development", "outputDirectory": tmp}
            output = io.StringIO()
            with patch.object(bridge, 'read_head', return_value=None), contextlib.redirect_stdout(output):
                self.assertEqual(bridge.run_pull_catalog(request, False), 0)
            doc = json.loads((Path(tmp) / 'shop-catalog.json').read_text())
            self.assertEqual(doc['products'], [])
            self.assertTrue(any(json.loads(line)['type'] == 'catalog' for line in output.getvalue().splitlines()))

    def test_head_without_shop_partition_returns_empty_baseline(self):
        root = json.dumps({"partitions": [], "releaseSeq": 9}).encode()
        head = {"releaseSeq": 9, "rootIndexHash": hashlib.sha256(root).hexdigest()}
        class Adapter:
            def fetch_root_index_bytes(self):
                return root
        with tempfile.TemporaryDirectory() as tmp:
            request = {"targetEnvironment": "development", "outputDirectory": tmp}
            with patch.object(bridge, 'read_head', return_value=head), \
                 patch.object(bridge, 'make_adapter', return_value=Adapter()), contextlib.redirect_stdout(io.StringIO()):
                self.assertEqual(bridge.run_pull_catalog(request, False), 0)
            metadata = json.loads((Path(tmp) / 'pull-manifest.json').read_text())
            self.assertEqual(metadata['releaseSeq'], 9)
            self.assertEqual(metadata['rootIndexHash'], head['rootIndexHash'])

    def fetch(self, payloads):
        images = [b'\xff\xd8\xff' + b'a', b'\xff\xd8\xff' + b'b']
        hashes = [hashlib.sha256(data).hexdigest() for data in images]
        with tempfile.TemporaryDirectory() as tmp:
            request = {"targetEnvironment": "development", "outputDirectory": tmp,
                       "mediaHashes": hashes}
            class Adapter:
                def fetch_media_bytes(self, digest):
                    value = payloads[hashes.index(digest)]
                    if isinstance(value, Exception):
                        raise value
                    return value
            output = io.StringIO()
            with patch.object(bridge, 'make_adapter', return_value=Adapter()), contextlib.redirect_stdout(output):
                code = bridge.run_fetch_media(request, False)
            manifest = json.loads((Path(tmp) / 'fetch-manifest.json').read_text())
            events = [json.loads(line) for line in output.getvalue().splitlines()]
            return code, manifest, events

    def test_partial_network_failure_keeps_progress(self):
        code, manifest, events = self.fetch([b'\xff\xd8\xffa', NetworkError('connection reset')])
        self.assertEqual(code, bridge.EXIT_NETWORK)
        self.assertEqual(len(manifest['downloaded']), 1)
        self.assertEqual(len(manifest['pending']), 1)
        self.assertEqual(manifest['missing'], [])
        self.assertTrue(any(e['type'] == 'media' for e in events))
        self.assertTrue(events[-1]['retryable'])

    def test_corruption_is_failure(self):
        code, manifest, events = self.fetch([b'wrong', b'\xff\xd8\xffb'])
        self.assertEqual(code, bridge.EXIT_VALIDATION)
        self.assertEqual(len(manifest['corrupt']), 1)
        self.assertNotEqual(events[-1]['outcome'], 'confirmed')

    def test_missing_is_distinct_from_network_failure(self):
        code, manifest, events = self.fetch([None, None])
        self.assertEqual(code, 0)
        self.assertEqual(len(manifest['missing']), 2)
        self.assertEqual(manifest['pending'], [])

    def test_lookup_failure_keeps_partial_result(self):
        code, manifest, _ = self.fetch([b'\xff\xd8\xffa', ProtocolError('ACCESS_DENIED')])
        self.assertEqual(code, bridge.EXIT_REFUSED)
        self.assertEqual(len(manifest['downloaded']), 1)
        self.assertEqual(len(manifest['pending']), 1)


if __name__ == '__main__':
    unittest.main()
