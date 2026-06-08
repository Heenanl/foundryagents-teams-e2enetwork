# Tests — Foundry → Teams Bridge

Verifies the APIM bridge routes correctly to the **private** Foundry activity endpoint.

## Setup

```powershell
# From the repo root
python -m venv .venv
.\.venv\Scripts\Activate.ps1
pip install -r tests/requirements.txt
```

## Configure

```powershell
Copy-Item tests/.env.template tests/.env
# Edit tests/.env with your gateway URL, project, and agent
```

Load the env vars (PowerShell):

```powershell
Get-Content tests/.env | Where-Object { $_ -and $_ -notmatch '^\s*#' } | ForEach-Object {
    $k, $v = $_ -split '=', 2
    [System.Environment]::SetEnvironmentVariable($k.Trim(), $v.Trim())
}
```

## Run

```powershell
python tests/test_bridge.py
```

Or with pytest:

```powershell
pip install pytest
pytest tests/test_bridge.py -v
```

## Interpreting results

| Status | Meaning | Result |
|---|---|---|
| **401** | Routed to Foundry; unsigned probe challenged by auth layer | ✅ PASS |
| 404 | Wrong APIM path/operation | ❌ FAIL |
| 500 | APIM cannot resolve/reach the private backend (DNS/VNet) | ❌ FAIL |
| 400 | Reached Foundry but request rejected (e.g. missing `api-version`) | ❌ FAIL |

> The test uses an **unsigned** request on purpose. A correctly routed unsigned
> request is challenged with **401** because Foundry validates the Bot Framework
> JWT itself. Real Bot Service traffic carries a valid JWT and returns **202**,
> with the agent reply delivered asynchronously via the Bot Service `serviceUrl`.
