"""Exercise the built API artifact in an isolated, synthetic Docker network."""
import json
import subprocess
import tempfile
import time
import uuid
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

def run(*args, check=True):
    return subprocess.run(args, text=True, capture_output=True, check=check).stdout

image = next(iter(json.loads((ROOT / ".images/build.json").read_text())["images"].values()))
name = "telegram-api-smoke-" + uuid.uuid4().hex[:12]
try:
    run("docker", "network", "create", "--internal", name)
    with tempfile.TemporaryDirectory() as directory:
        secret = Path(directory) / "password"
        secret.write_text("00" * 32)
        run("docker", "run", "-d", "--name", name, "--platform", "linux/amd64",
            "--network", name, "--add-host", "entry:127.0.0.1", "--cap-add", "NET_ADMIN",
            "-e", "TELEGRAM_API_ID=1234", "-e", "TELEGRAM_API_HASH=" + "00" * 16,
            "-e", "TELEGRAM_LOCAL=1", "--mount",
            "type=bind,src=" + str(secret) + ",dst=/run/secrets/telegram-socks-password,readonly", image)
        for attempt in range(30):
            result = subprocess.run(["docker", "exec", name, "wget", "-S", "-O", "/dev/null",
                "http://127.0.0.1:8081/"], capture_output=True, text=True)
            if "HTTP/1.1 404" in result.stderr:
                break
            time.sleep(1)
        else:
            raise RuntimeError("API HTTP listener did not start")
        assert "default " in run("docker", "exec", name, "ip", "route")
        run("docker", "exec", name, "iptables", "-t", "nat", "-C", "TELEGRAM_API_NAT",
            "-d", "149.154.160.0/20", "-p", "tcp", "--dport", "443", "-j", "REDIRECT", "--to-ports", "12345")
        run("docker", "exec", name, "iptables", "-C", "TELEGRAM_API_OUT", "-d", "127.0.0.1",
            "-p", "tcp", "--dport", "12345", "-j", "ACCEPT")
        # An unrelated child must not end supervision of the API/proxy.
        run("docker", "exec", name, "sh", "-c", "sleep 1 &")
        time.sleep(2)
        assert json.loads(run("docker", "inspect", name))[0]["State"]["Running"]
        run("docker", "exec", name, "killall", "redsocks")
        for attempt in range(10):
            if not json.loads(run("docker", "inspect", name))[0]["State"]["Running"]:
                break
            time.sleep(1)
        else:
            raise RuntimeError("API stayed active after its proxy stopped")
    print("Built API smoke test passed: listener, route, redirect, filtering and supervision")
finally:
    run("docker", "rm", "-f", name, check=False)
    run("docker", "network", "rm", name, check=False)
