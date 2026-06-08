"""
test_bridge.py

Verifies the Foundry → Teams APIM bridge routes correctly to the PRIVATE Foundry
activity endpoint.

Why an unsigned request returns 401 (and that's a PASS):
    Foundry validates the Bot Framework JWT itself. An unauthenticated probe that
    is routed correctly reaches Foundry's auth layer and is challenged with 401.
    - 401  => bridge + path + api-version are correct (auth challenge only)   PASS
    - 404  => wrong path/operation on APIM                                     FAIL
    - 500  => APIM cannot resolve/reach the private backend (DNS/VNet)         FAIL
    - 400  => reached Foundry but request rejected (e.g. missing api-version)  FAIL

Real Bot Service traffic carries a valid JWT and returns 202 (accepted); the
agent reply is delivered asynchronously via the Bot Service serviceUrl.

Config via environment variables (see .env.template):
    APIM_GATEWAY         e.g. https://apim-foundry-bridge.azure-api.net
    API_PATH             default 'foundry'
    PROJECT              Foundry project name
    AGENT                Foundry agent name
    FOUNDRY_API_VERSION  default '2025-11-15-preview'
"""
import os
import sys

import requests

GATEWAY = os.environ.get("APIM_GATEWAY", "").rstrip("/")
API_PATH = os.environ.get("API_PATH", "foundry")
PROJECT = os.environ.get("PROJECT", "")
AGENT = os.environ.get("AGENT", "")
API_VERSION = os.environ.get("FOUNDRY_API_VERSION", "2025-11-15-preview")

ACTIVITY = {
    "type": "message",
    "text": "bridge-test-ping",
    "from": {"id": "test-user"},
    "conversation": {"id": "test-conversation"},
    "recipient": {"id": "bot"},
    "serviceUrl": "https://smba.trafficmanager.net/",
}


def _require_config():
    missing = [k for k, v in {
        "APIM_GATEWAY": GATEWAY,
        "PROJECT": PROJECT,
        "AGENT": AGENT,
    }.items() if not v]
    if missing:
        print(f"ERROR: missing required env vars: {', '.join(missing)}")
        print("Copy .env.template to .env, fill it in, and load it before running.")
        sys.exit(2)


def build_url() -> str:
    return (
        f"{GATEWAY}/{API_PATH}/api/projects/{PROJECT}/agents/{AGENT}"
        f"/endpoint/protocols/activityprotocol?api-version={API_VERSION}"
    )


def test_bridge_routes_to_foundry():
    """Unsigned activity should be challenged (401) — proves correct routing."""
    _require_config()
    url = build_url()
    resp = requests.post(url, json=ACTIVITY, timeout=30)
    assert resp.status_code == 401, (
        f"Expected 401 (auth challenge => correct routing). Got {resp.status_code}.\n"
        f"  404 => wrong APIM path/operation\n"
        f"  500 => APIM cannot reach private Foundry (DNS/VNet)\n"
        f"  400 => reached Foundry but request rejected (api-version?)\n"
        f"Body: {resp.text[:300]}"
    )


def main() -> int:
    _require_config()
    url = build_url()
    print(f"POST {url}")
    try:
        resp = requests.post(url, json=ACTIVITY, timeout=30)
    except requests.RequestException as exc:
        print(f"FAIL: request error: {exc}")
        return 1

    code = resp.status_code
    if code == 401:
        print("PASS: 401 — bridge routes to Foundry; unsigned request correctly challenged.")
        return 0
    if code == 404:
        print("FAIL: 404 — APIM operation/path mismatch.")
    elif code == 500:
        print("FAIL: 500 — APIM cannot resolve/reach the private Foundry backend (DNS/VNet).")
    elif code == 400:
        print(f"FAIL: 400 — reached Foundry but rejected. Body: {resp.text[:300]}")
    else:
        print(f"UNEXPECTED: {code}. Body: {resp.text[:300]}")
    return 1


if __name__ == "__main__":
    sys.exit(main())
