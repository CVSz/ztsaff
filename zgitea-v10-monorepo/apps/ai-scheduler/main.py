from dataclasses import dataclass


@dataclass
class Metrics:
    queue_depth: int
    cpu_pct: float
    avg_latency_ms: float


def predict_workers(m: Metrics, min_workers: int = 2, max_workers: int = 100) -> int:
    baseline = max(min_workers, m.queue_depth // 20 + 1)
    if m.cpu_pct > 75 or m.avg_latency_ms > 500:
        baseline += 2
    return min(max_workers, baseline)


if __name__ == "__main__":
    sample = Metrics(queue_depth=120, cpu_pct=64.0, avg_latency_ms=420)
    workers = predict_workers(sample)
    print({"predicted_workers": workers})
