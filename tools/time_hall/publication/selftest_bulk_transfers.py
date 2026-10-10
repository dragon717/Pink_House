#!/usr/bin/env python3
"""批量传输、恢复与子进程终止回归；仅临时夹具，不读凭证或写云端。"""
import argparse
import contextlib
import hashlib
import io
import json
import os
from pathlib import Path
import signal
import subprocess
import sys
import tempfile
import threading
import time
import unittest
from unittest.mock import patch

import ops_publish_bridge as bridge
import publish_adapters as pa
import publish_cloudkit as publisher
from protocol import ProtocolError


class BulkTransferTests(unittest.TestCase):
    def adapter(self, post):
        adapter = pa.CloudKitWebServicesAdapter(pa.Credentials("iCloud.test", "development", "test", "test"),
                                               apply=False, http_post=post)
        adapter._headers = lambda *args: {}
        return adapter

    def test442ImagesUseThreeMetadataRequests(self):
        calls = []
        def post(url, body, headers):
            records = json.loads(body)["records"]
            calls.append(len(records))
            return {"records": [{"recordName": r["recordName"], "fields": {
                "asset": {"value": {"downloadURL": "https://example.com/image"}}}} for r in records]}
        assets = self.adapter(post).media_assets_many([str(i) for i in range(442)])
        self.assertEqual(len(assets), 442)
        self.assertEqual(calls, [200, 200, 42])

    def testMissingPermissionAndIncompleteResponseStayDistinct(self):
        missing = {"records": [{"recordName": "th.media.a", "serverErrorCode": "NOT_FOUND"}]}
        self.assertEqual(self.adapter(lambda *args: missing).media_assets_many(["a"]), {})
        for response in ({"records": [{"recordName": "th.media.a", "serverErrorCode": "ACCESS_DENIED"}]},
                         {"records": [{"recordName": "th.media.a"}]}):
            with self.assertRaises(ProtocolError):
                self.adapter(lambda *args: response).media_assets_many(["a", "b"])

    def testDownloadsUseBatchURLsAndAtMostFourWorkers(self):
        lock = threading.Lock()
        active = peak = 0
        class Adapter:
            def media_assets_many(self, hashes):
                return {h: {"hash": h} for h in hashes}
            def _download_asset(self, value):
                nonlocal active, peak
                with lock:
                    active += 1
                    peak = max(peak, active)
                time.sleep(.02)
                with lock:
                    active -= 1
                return value["hash"].encode()
            def fetch_media_bytes(self, digest):
                raise AssertionError("不应退化成逐张 lookup")
        results = list(bridge.fetch_media_items(Adapter(), [str(i) for i in range(9)]))
        self.assertEqual([h for h, _ in results], [str(i) for i in range(9)])
        self.assertEqual(peak, 4)

    def testCheckpointSurvivesAbruptInterruptionWithoutFinalMediaEvent(self):
        image = b'\xff\xd8\xffimage'
        hashes = [hashlib.sha256(image).hexdigest(), 'b' * 64]
        with tempfile.TemporaryDirectory() as tmp:
            def interrupted(adapter, ordered):
                yield hashes[0], image
                saved = json.loads((Path(tmp) / "fetch-manifest.json").read_text())
                self.assertEqual(len(saved["downloaded"]), 1)
                self.assertEqual(saved["pending"], [hashes[1]])
                raise KeyboardInterrupt()
            request = {"targetEnvironment": "development", "outputDirectory": tmp, "mediaHashes": hashes}
            with patch.object(bridge, "make_adapter", return_value=object()), \
                 patch.object(bridge, "fetch_media_items", interrupted), contextlib.redirect_stdout(io.StringIO()):
                with self.assertRaises(KeyboardInterrupt):
                    bridge.run_fetch_media(request, False)
            saved = json.loads((Path(tmp) / "fetch-manifest.json").read_text())
            self.assertEqual(len(saved["downloaded"]), 1)
            self.assertEqual(saved["pending"], [hashes[1]])

    def testUploadUsesOneInventoryAndBoundedConcurrency(self):
        lock = threading.Lock()
        active = peak = 0
        inventory = []
        uploaded = []
        class Adapter:
            def media_exists_many(self, hashes):
                inventory.append(hashes)
                return {"0"}
            def put_media(self, digest, path, meta):
                nonlocal active, peak
                with lock:
                    active += 1
                    peak = max(peak, active)
                time.sleep(.02)
                with lock:
                    active -= 1
                    uploaded.append(digest)
        with tempfile.TemporaryDirectory() as tmp, contextlib.redirect_stdout(io.StringIO()):
            path = Path(tmp) / "image.jpg"
            path.write_bytes(b'image')
            media = [{"contentHash": str(i), "filePath": path, "meta": {}} for i in range(10)]
            self.assertEqual(publisher.upload_missing_media(Adapter(), media), 9)
        self.assertEqual(len(inventory), 1)
        self.assertEqual(set(uploaded), {str(i) for i in range(1, 10)})
        self.assertEqual(peak, 4)

    def testUploadFailureCannotReachReleaseHead(self):
        class Adapter:
            def describe(self): return "offline test"
            def fetch_current_release(self): return {"releaseSeq": 8, "changeTag": "tag8"}
            def media_exists_many(self, hashes): return set()
            def put_media(self, *args): raise pa.NetworkError("interrupted upload")
            def put_release(self, *args): raise AssertionError("不能切头")
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "image.jpg"
            path.write_bytes(b'image')
            args = argparse.Namespace(release=Path(tmp), apply=True, dry_run=False, quiet=True,
                adapter="cloudkit", environment="development", print_requests=False, filesystem_root=None)
            media = [{"contentHash": "a", "filePath": path, "meta": {}}]
            with patch.object(publisher, "revalidate", return_value=({"releaseSeq": 9}, b'root', {}, [])), \
                 patch.object(publisher, "make_adapter", return_value=Adapter()), \
                 patch.object(publisher, "collect_assets", return_value=([], media)), \
                 contextlib.redirect_stdout(io.StringIO()):
                with self.assertRaises(pa.NetworkError):
                    publisher.publish(args)

    def testSuccessfulRetryDoesNotRethrowPreviousUploadError(self):
        adapter = self.adapter(lambda *args: {})
        adapter.apply = True
        class Response(io.BytesIO):
            def __enter__(self): return self
            def __exit__(self, *args): self.close()
        response = Response(b'{"singleFile":{"receipt":"ok"}}')
        with patch.object(pa, "open_https", side_effect=[pa.NetworkError("EOF"), response]), \
             patch("time.sleep"):
            self.assertEqual(adapter._upload_file("https://example.com", b'file', "file.jpg"), {"receipt": "ok"})

    def testFreshBatchReadbackMustPassBeforeConditionalHeadUpdate(self):
        for readable in [False, True]:
            with self.subTest(readable=readable), tempfile.TemporaryDirectory() as tmp:
                calls = []
                class Adapter:
                    def describe(self): return "offline test"
                    def fetch_current_release(self):
                        return {"releaseSeq": 9 if "head" in calls else 8, "changeTag": "tag8"}
                    def media_exists_many(self, hashes):
                        calls.append("inventory")
                        return {"a"} if readable and calls.count("inventory") == 2 else set()
                    def put_media(self, *args): calls.append("media")
                    def put_release(self, release, root, expected):
                        self_expected = expected
                        if self_expected != "tag8": raise AssertionError("条件更新不能丢掉原 changeTag")
                        calls.append("head")
                        return "tag9"
                path = Path(tmp) / "image.jpg"
                path.write_bytes(b'image')
                args = argparse.Namespace(release=Path(tmp), apply=True, dry_run=False, quiet=True,
                    adapter="cloudkit", environment="development", print_requests=False, filesystem_root=None, receipt=None)
                media = [{"contentHash": "a", "filePath": path, "meta": {}, "recordName": "th.media.a"}]
                with patch.object(publisher, "revalidate", return_value=({"releaseSeq": 9}, b'root', {}, [])), \
                     patch.object(publisher, "make_adapter", return_value=Adapter()), \
                     patch.object(publisher, "collect_assets", return_value=([], media)), \
                     contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
                    code = publisher.publish(args)
                self.assertEqual(code, 0 if readable else publisher.EXIT_CONFLICT)
                self.assertEqual(calls, ["inventory", "media", "inventory"] + (["head"] if readable else []))

    def testStoppingBridgeAlsoStopsPublisherChild(self):
        with tempfile.TemporaryDirectory() as tmp:
            worker = Path(tmp) / "worker.py"
            worker.write_text("import os,time\nprint(os.getpid())\ntime.sleep(30)\n", encoding="utf-8")
            code = "import sys; sys.path.insert(0,sys.argv[1]); import ops_publish_bridge as b; b.run_child([sys.executable,sys.argv[2]],False)"
            parent = subprocess.Popen([sys.executable, "-u", "-c", code, str(Path(bridge.__file__).parent), str(worker)],
                                      stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
            try:
                event = json.loads(parent.stdout.readline())
                child_pid = int(event["message"])
                parent.send_signal(signal.SIGTERM)
                parent.communicate(timeout=6)
                self.assertEqual(parent.returncode, 128 + signal.SIGTERM)
                with self.assertRaises(ProcessLookupError):
                    os.kill(child_pid, 0)
            finally:
                if parent.poll() is None:
                    parent.kill()
                    parent.communicate()


if __name__ == "__main__":
    unittest.main(verbosity=2)
