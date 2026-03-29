import unittest
import importlib.util
from pathlib import Path


def load_module(path: str):
    spec = importlib.util.spec_from_file_location("mod", path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


class SchedulerTests(unittest.TestCase):
    def test_predict_workers_increases_for_load(self):
        mod = load_module(str(Path(__file__).resolve().parents[1] / "apps/ai-scheduler/main.py"))
        metrics = mod.Metrics(queue_depth=200, cpu_pct=85.0, avg_latency_ms=700)
        self.assertGreaterEqual(mod.predict_workers(metrics), 10)


if __name__ == "__main__":
    unittest.main()
