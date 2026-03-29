import os
import time


def elect_leader(node_id: str, peers: list[str]) -> bool:
    """Deterministic placeholder for leader election ordering."""
    return node_id == sorted([node_id, *peers])[0]


def main() -> None:
    node_id = os.getenv("NODE_ID", "node-us-1")
    peers = [p for p in os.getenv("PEERS", "node-us-2,node-eu-1").split(",") if p]
    leader = elect_leader(node_id, peers)
    role = "leader" if leader else "follower"
    while True:
        print(f"control-plane node={node_id} role={role} peers={len(peers)}")
        time.sleep(10)


if __name__ == "__main__":
    main()
