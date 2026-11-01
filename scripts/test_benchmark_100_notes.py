"""Offline regression coverage for authenticated benchmark requests."""

import contextlib
import io
import json
import os
import unittest
import urllib.request
import urllib.response
from email.message import Message
from unittest.mock import patch

with patch.dict(os.environ, {"TE_TEST_BASE_URL": "https://api.example.test/v1"}):
    with patch("os.path.exists", return_value=False):
        from benchmark_100_notes import ResilientGeminiClient


class BenchmarkRequestSecurityTest(unittest.TestCase):
    def setUp(self):
        self.client = ResilientGeminiClient(
            "synthetic-test-token", "https://api.example.test/v1", ["test-model"]
        )
        self.client.min_interval = 0
        self.requests = []
        self.response_data = {"choices": [{"message": {"content": "Test reply"}}]}

    def response(self, request, status=200, location=None):
        headers = Message()
        if location is not None:
            headers["Location"] = location
        response = urllib.response.addinfourl(
            io.BytesIO(json.dumps(self.response_data).encode("utf-8")),
            headers,
            request.full_url,
            status,
        )
        response.msg = "Test response"
        return response

    def complete(self, transport):
        # Replace only network I/O; urllib still processes responses and redirects.
        with patch.object(urllib.request.HTTPSHandler, "https_open", side_effect=transport):
            with patch.object(urllib.request.HTTPHandler, "http_open", side_effect=transport):
                with contextlib.redirect_stdout(io.StringIO()):
                    return self.client.complete(
                        [{"role": "user", "content": "Test prompt"}]
                    )

    def test_https_completion_preserves_request_and_result(self):
        def transport(request):
            self.requests.append(request)
            return self.response(request)

        result = self.complete(transport)

        self.assertEqual(result["data"], self.response_data)
        self.assertEqual(result["model"], "test-model")
        self.assertIsNone(result["error"])
        self.assertEqual(len(self.requests), 1)
        request = self.requests[0]
        self.assertEqual(request.full_url, "https://api.example.test/v1/chat/completions")
        self.assertEqual(request.get_method(), "POST")
        self.assertEqual(request.get_header("Authorization"), "Bearer synthetic-test-token")
        self.assertEqual(request.get_header("Content-type"), "application/json")
        self.assertEqual(
            json.loads(request.data),
            {
                "model": "test-model",
                "messages": [{"role": "user", "content": "Test prompt"}],
                "temperature": 0.2,
            },
        )

    def test_redirects_never_send_a_second_request(self):
        for status in (301, 302, 303, 307, 308):
            for location in (
                "http://observer.example.test/capture",
                "https://observer.example.test/capture",
                "//observer.example.test/capture",
                "/relocated",
            ):
                with self.subTest(status=status, location=location):
                    self.requests.clear()

                    def transport(request):
                        self.requests.append(request)
                        if len(self.requests) == 1:
                            return self.response(request, status, location)
                        return self.response(request)

                    result = self.complete(transport)

                    self.assertEqual(
                        [request.full_url for request in self.requests],
                        ["https://api.example.test/v1/chat/completions"],
                        "An authenticated request reached a redirect destination",
                    )
                    self.assertIsNone(result["data"])
                    self.assertIsNotNone(result["error"])


if __name__ == "__main__":
    unittest.main()
