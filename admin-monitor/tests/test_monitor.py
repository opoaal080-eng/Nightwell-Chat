import importlib.util
import pathlib
import threading
import unittest
import urllib.error
import urllib.request

ROOT = pathlib.Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("nightwell_monitor", ROOT / "monitor.py")
monitor = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(monitor)


class MonitorTests(unittest.TestCase):
    def test_rate(self):
        self.assertIsNone(monitor.rate(120, None, 4))
        self.assertIsNone(monitor.rate(120, 100, 0))
        self.assertEqual(monitor.rate(600, 100, 2), 250.0)
        self.assertEqual(monitor.rate(90, 100, 2), 0)

    def test_metrics_shape(self):
        result = monitor.collect()
        self.assertIn("cpu", result)
        self.assertIn("memory", result)
        self.assertIn("network", result)
        self.assertIn("services", result)
        self.assertTrue(0 <= result["memory"]["percent"] <= 100)
        self.assertGreater(result["memory"]["total_bytes"], 0)

    def test_authentication(self):
        server = monitor.MonitorHTTPServer(("127.0.0.1", 0), "x" * 40)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        try:
            url = f"http://127.0.0.1:{server.server_port}/v1/system/metrics"
            with self.assertRaises(urllib.error.HTTPError) as error:
                urllib.request.urlopen(url, timeout=5)
            self.assertEqual(error.exception.code, 401)
            req = urllib.request.Request(url, headers={"Authorization": "Bearer " + "x" * 40})
            with urllib.request.urlopen(req, timeout=8) as response:
                self.assertEqual(response.status, 200)
                self.assertEqual(response.headers.get("Cache-Control"), "no-store")
        finally:
            server.shutdown()
            server.server_close()
            thread.join(timeout=3)


if __name__ == "__main__":
    unittest.main()
