#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""本机代理失效时的 CloudKit 连接回退；离线运行，不读取凭证或写云端。"""
import ssl
import unittest
from unittest.mock import patch

import publish_adapters as pa


class FakeSocket:
    def __init__(self, opened):
        self.address = None
        self.closed = False
        opened.append(self)

    def settimeout(self, timeout):
        self.timeout = timeout

    def connect(self, address):
        self.address = address[0]

    def close(self):
        self.closed = True


class FakeTLS:
    def __init__(self, failures):
        self.failures = failures
        self.server_names = []

    def wrap_socket(self, sock, server_hostname):
        self.server_names.append(server_hostname)
        if sock.address in self.failures:
            raise self.failures[sock.address]
        return sock


class LoopbackProxyTests(unittest.TestCase):
    def setUp(self):
        pa._DIRECT_ROUTES.clear()

    def connect(self, failures, proxy="127.0.0.1", target="api.apple-cloudkit.com", tunnel_error=None):
        connection = pa._FailoverHTTPSConnection(proxy, port=9674, timeout=3)
        connection.set_tunnel(target, 443)
        context = FakeTLS(failures)
        connection._context = context
        tunnel_calls = []

        def tunnel():
            tunnel_calls.append(target)
            if tunnel_error:
                raise tunnel_error

        connection._tunnel = tunnel
        opened = []
        resolved = []

        def addresses(host, port):
            resolved.append((host, port))
            ips = [proxy] if host == proxy else ["17.248.216.28", "17.248.216.69"]
            return [(2, 1, 6, (ip, port)) for ip in ips]

        with patch.object(pa, "resolved_tcp_addresses", addresses), \
                patch.object(pa.socket, "socket", lambda *args: FakeSocket(opened)):
            try:
                connection.connect()
                error = None
            except Exception as caught:
                error = caught
        return connection, context, opened, resolved, tunnel_calls, error

    def testBrokenLocalProxyFallsBackToCloudKitWithOriginalSNI(self):
        connection, context, opened, resolved, tunnels, error = self.connect({
            "127.0.0.1": ssl.SSLEOFError("proxy EOF")})
        self.assertIsNone(error)
        self.assertEqual(connection.sock.address, "17.248.216.28")
        self.assertTrue(opened[0].closed)
        self.assertEqual(resolved, [("127.0.0.1", 9674), ("api.apple-cloudkit.com", 443)])
        self.assertEqual(context.server_names, ["api.apple-cloudkit.com"] * 2)
        self.assertEqual(tunnels, ["api.apple-cloudkit.com"])

    def testHealthyProxyIsUsedWithoutDirectConnection(self):
        connection, _, _, resolved, _, error = self.connect({})
        self.assertIsNone(error)
        self.assertEqual(connection.sock.address, "127.0.0.1")
        self.assertEqual(resolved, [("127.0.0.1", 9674)])

    def testBatchReusesSuccessfulDirectRouteAndRestoresReadTimeout(self):
        self.connect({"127.0.0.1": ssl.SSLEOFError("proxy EOF")})
        connection, _, _, resolved, tunnels, error = self.connect({})
        self.assertIsNone(error)
        self.assertEqual(resolved, [("api.apple-cloudkit.com", 443)])
        self.assertEqual(tunnels, [])
        self.assertEqual(connection.sock.timeout, 3)

    def testExpiredRouteProbesProxyAgain(self):
        pa._DIRECT_ROUTES[("127.0.0.1", 9674, "api.apple-cloudkit.com")] = 0
        connection, _, _, _, tunnels, error = self.connect({})
        self.assertIsNone(error)
        self.assertEqual(connection.sock.address, "127.0.0.1")
        self.assertEqual(len(tunnels), 1)

    def testSystemPythonSocketTimeoutTriggersFallback(self):
        connection, _, _, _, _, error = self.connect({"127.0.0.1": pa.socket.timeout("TLS handshake timed out")})
        self.assertIsNone(error)
        self.assertEqual(connection.sock.address, "17.248.216.28")

    def testConnectionBudgetDoesNotMultiplyByAddressCount(self):
        with patch.object(pa, "_CONNECTION_BUDGET", 0):
            _, _, opened, _, _, error = self.connect({})
        self.assertIsInstance(error, pa.NetworkError)
        self.assertEqual(opened, [])
        self.assertIn("20 秒", str(error))

    def testDirectConnectionStillTriesOtherEdgesAfterTLSFailure(self):
        connection, _, opened, _, _, error = self.connect({
            "127.0.0.1": ssl.SSLEOFError("proxy EOF"),
            "17.248.216.28": ConnectionResetError("bad edge")})
        self.assertIsNone(error)
        self.assertEqual(connection.sock.address, "17.248.216.69")
        self.assertTrue(all(sock.closed for sock in opened[:2]))

    def testCertificateFailureDoesNotTriggerDirectFallback(self):
        _, _, opened, resolved, _, error = self.connect({
            "127.0.0.1": ssl.SSLCertVerificationError("invalid certificate")})
        self.assertIsInstance(error, ssl.SSLCertVerificationError)
        self.assertEqual(len(resolved), 1)
        self.assertTrue(opened[0].closed)

    def testRemoteProxyOrUnrelatedTargetDoesNotTriggerDirectFallback(self):
        for proxy, target in [("192.0.2.10", "api.apple-cloudkit.com"), ("127.0.0.1", "example.com")]:
            with self.subTest(proxy=proxy, target=target):
                _, _, _, resolved, _, error = self.connect({proxy: ssl.SSLEOFError("EOF")}, proxy, target)
                self.assertIsInstance(error, pa.NetworkError)
                self.assertEqual(len(resolved), 1)
                self.assertIn("代理", str(error))

    def testExplicitProxyRejectionDoesNotTriggerDirectFallback(self):
        _, _, _, resolved, _, error = self.connect({}, tunnel_error=OSError("Tunnel connection failed: 407"))
        self.assertIsInstance(error, pa.NetworkError)
        self.assertEqual(len(resolved), 1)
        self.assertIn("407", str(error))

    def testBothRoutesFailAndReportBothCauses(self):
        _, _, opened, _, _, error = self.connect({
            "127.0.0.1": ssl.SSLEOFError("proxy EOF"),
            "17.248.216.28": ConnectionResetError("edge one"),
            "17.248.216.69": TimeoutError("edge two")})
        self.assertIsInstance(error, pa.NetworkError)
        self.assertIn("本机代理 127.0.0.1:9674", str(error))
        self.assertIn("直连 api.apple-cloudkit.com 也失败", str(error))
        self.assertTrue(all(sock.closed for sock in opened))

    def testAppleMediaHostIsIncludedWithoutAcceptingLookalikeDomains(self):
        self.assertTrue(pa._is_cloudkit_host("cvws.icloud-content.com"))
        self.assertFalse(pa._is_cloudkit_host("api.apple-cloudkit.com.example.com"))
        self.assertFalse(pa._is_cloudkit_host("fakeicloud-content.com"))
        self.assertTrue(pa._is_loopback_proxy("::1"))
        self.assertTrue(pa._is_loopback_proxy("localhost"))
        self.assertFalse(pa._is_loopback_proxy("proxy.example.com"))


if __name__ == "__main__":
    unittest.main(verbosity=2)
