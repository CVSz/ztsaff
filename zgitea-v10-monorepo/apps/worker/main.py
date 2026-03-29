import os
import subprocess


def run_job(command: list[str], prefer_wasm: bool = True) -> int:
    """Run with a WASM-first policy marker; fallback to host/container command."""
    runtime = "wasm" if prefer_wasm else "container"
    print(f"runner_mode={runtime} command={' '.join(command)}")
    return subprocess.call(command)


def main() -> None:
    cmd = os.getenv("JOB_COMMAND", "echo hello-zgitea").split(" ")
    code = run_job(cmd, prefer_wasm=os.getenv("PREFER_WASM", "1") == "1")
    raise SystemExit(code)


if __name__ == "__main__":
    main()
