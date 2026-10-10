#!/usr/bin/env python3
"""同步故障回归：部分下载可接收，错误不能伪装成不存在。全程离线。"""
import contextlib
import hashlib
import io
import json
import subprocess
import tarfile
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

import ops_publish_bridge as bridge
from build_release import collect_shop_catalog_media
from protocol import ProtocolError
from publish_adapters import CredentialError, CloudKitWebServicesAdapter, Credentials, NetworkError, existing_records


class SyncTests(unittest.TestCase):
    def test_first_publication_builds_without_remote_manifest_even_if_stale_file_exists(self):
        # 真跑构建器，发布器截断：复现首次发布传入不存在清单造成的失败，
        # 同时确保上次环境留下的清单不会污染这次纯本地输入。
        doc = {"version": 1, "shops": [{"id": "shop", "name": "验收店家"}],
               "series": [], "products": [], "variants": [], "sizeCharts": [],
               "saleEvents": [], "assets": [], "styleProfiles": []}
        with tempfile.TemporaryDirectory() as tmp:
            directory = Path(tmp)
            archive = directory / 'fixture.tar'
            data = json.dumps(doc).encode('utf-8')
            with tarfile.open(archive, 'w', format=tarfile.USTAR_FORMAT) as tar:
                member = tarfile.TarInfo('shop-catalog.json')
                member.size = len(data)
                tar.addfile(member, io.BytesIO(data))
            for stale in (False, True):
                input_dir = directory / ('stale-input' if stale else 'fresh-input')
                input_dir.mkdir()
                if stale:
                    (input_dir / 'known-remote-media.json').write_text('invalid stale evidence')
                request = {"requestID": "first-publish", "jobID": "first-publish",
                           "draftID": "first-publish", "targetEnvironment": "production", "dryRun": True,
                           "archivePath": str(archive), "inputDirectory": str(input_dir),
                           "outputDirectory": str(directory / ('stale-output' if stale else 'fresh-output')),
                           "receiptPath": str(directory / 'receipt.json'), "releaseSeq": 1,
                           "payloadHash": bridge.sha256_file(archive), "baseReleaseSeq": 0}
                build_results = []
                def run_child(argv, quiet):
                    if Path(argv[1]).name == 'build_release.py':
                        result = subprocess.run(argv, capture_output=True, text=True, encoding='utf-8')
                        build_results.append(result)
                        return result.returncode, []
                    return 1, []  # 不执行远端发布
                with patch.object(bridge, 'read_head', return_value=None), \
                     patch.object(bridge, 'run_child', side_effect=run_child), \
                     contextlib.redirect_stdout(io.StringIO()):
                    bridge.run_publish(request, True)
                self.assertEqual(len(build_results), 1)
                self.assertEqual(build_results[0].returncode, 0,
                                 build_results[0].stdout + build_results[0].stderr)

    def test_observed_empty_baseline_allows_first_publication(self):
        self.assertEqual(bridge.baseline_mismatches(
            {"baseReleaseSeq": 0, "baseRootIndexHash": None}, None), [])
        self.assertEqual(bridge.baseline_mismatches(
            {"baseReleaseSeq": "0", "baseRootIndexHash": ""}, None), [])

    def test_unknown_or_previously_published_baseline_never_becomes_empty_baseline(self):
        for request in ({}, {"baseReleaseSeq": 2},
                        {"baseReleaseSeq": 0, "baseRootIndexHash": "a" * 64}):
            self.assertTrue(bridge.baseline_mismatches(request, None))

    def test_empty_baseline_is_stale_if_another_publisher_created_head(self):
        self.assertTrue(bridge.baseline_mismatches(
            {"baseReleaseSeq": 0, "baseRootIndexHash": None},
            {"releaseSeq": 1, "rootIndexHash": "a" * 64}))

    def test_authentication_failure_cannot_be_treated_as_empty_production(self):
        with tempfile.TemporaryDirectory() as tmp:
            directory = Path(tmp)
            archive = directory / 'release.tar'
            archive.write_bytes(b'frozen archive')
            request = {"targetEnvironment": "production", "dryRun": False,
                       "archivePath": str(archive), "inputDirectory": str(directory / 'input'),
                       "outputDirectory": str(directory / 'output'),
                       "receiptPath": str(directory / 'receipt.json'), "releaseSeq": 1,
                       "payloadHash": bridge.sha256_file(archive),
                       "baseReleaseSeq": 0, "baseRootIndexHash": None}
            with patch.object(bridge, 'read_head', side_effect=CredentialError('HTTP 401')), \
                 patch.object(bridge, 'run_child') as child, contextlib.redirect_stdout(io.StringIO()):
                self.assertEqual(bridge.run_publish(request, True), bridge.EXIT_REFUSED)
                child.assert_not_called()

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
