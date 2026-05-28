#!/usr/bin/env python3
"""Docs publishing helper for meta-pantavisor CI.

Commands:

  upload-asset <repo> <tag> <file> <token>
      Upload a file to an existing GitHub release.
      Prints the public download URL on success.

      repo   — owner/name  e.g. pantavisor/meta-pantavisor
      tag    — release tag e.g. v23
      file   — path to the file to upload
      token  — GitHub token with contents:write on the repo

  trigger-ingest <artifact_url> <filename> <token>
      Trigger docs-ingest.yml on pantavisor/docs.pantavisor.

      artifact_url — public download URL of the .docs.tar.zst file
      filename     — e.g. pantavisor-starter-raspberrypi-armv8.abc1234+v23.docs.tar.zst
      token        — GitHub token with actions:write on pantavisor/docs.pantavisor
                     (PANTAVISOR_DOC_SYNC secret)
"""
import sys
import json
import urllib.request
from pathlib import Path

DOCS_REPO = "pantavisor/docs.pantavisor"
WORKFLOW   = "docs-ingest.yml"
REF        = "master"


def _api(url, token, method="GET", data=None, content_type="application/json"):
    req = urllib.request.Request(
        url,
        data=data,
        method=method,
        headers={
            "Authorization": f"Bearer {token}",
            "Accept": "application/vnd.github+json",
            "Content-Type": content_type,
        },
    )
    with urllib.request.urlopen(req) as resp:
        return json.loads(resp.read())


def upload_asset(repo, tag, filepath, token):
    asset = Path(filepath)
    release = _api(f"https://api.github.com/repos/{repo}/releases/tags/{tag}", token)
    upload_url = release["upload_url"].split("{")[0]
    with asset.open("rb") as fh:
        _api(
            f"{upload_url}?name={asset.name}",
            token,
            method="POST",
            data=fh.read(),
            content_type="application/octet-stream",
        )
    print(f"https://github.com/{repo}/releases/download/{tag}/{asset.name}")


def trigger_ingest(artifact_url, filename, token):
    payload = json.dumps({
        "ref": REF,
        "inputs": {"artifact_url": artifact_url, "filename": filename},
    }).encode()
    _api(
        f"https://api.github.com/repos/{DOCS_REPO}/actions/workflows/{WORKFLOW}/dispatches",
        token,
        method="POST",
        data=payload,
    )
    print(f"Triggered {WORKFLOW} on {DOCS_REPO} for {filename}")


COMMANDS = {
    "upload-asset":    (upload_asset,    ["repo", "tag", "file", "token"]),
    "trigger-ingest":  (trigger_ingest,  ["artifact_url", "filename", "token"]),
}

if __name__ == "__main__":
    if len(sys.argv) < 2 or sys.argv[1] not in COMMANDS:
        print(__doc__)
        sys.exit(1)

    cmd, (fn, params) = sys.argv[1], COMMANDS[sys.argv[1]]
    args = sys.argv[2:]

    if len(args) != len(params):
        sys.exit(f"Usage: upload-docs.py {cmd} {' '.join(f'<{p}>' for p in params)}")

    fn(*args)
