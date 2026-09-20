#!/usr/bin/env python3
"""Producer-side check: a published wheel filename may never change bytes."""

from __future__ import annotations

import json
import os
from pathlib import Path
import re
from typing import Callable, Sequence
import urllib.error
import urllib.request

from release_manifest import (
    MANIFEST_NAME,
    ReleaseManifestError,
    SEMVER_RE,
    TAG_PREFIX,
    validate_manifest,
)


GITHUB_REPO = "gdombiak/AstroViewingConditions"
RELEASES_API = (
    f"https://api.github.com/repos/{GITHUB_REPO}/releases?per_page=100"
)
DOWNLOAD_TEMPLATE = (
    f"https://github.com/{GITHUB_REPO}/releases/download/{{tag}}/{{filename}}"
)
USER_AGENT = "Astronomer-Release-Validate/1"
NEXT_LINK = re.compile(r'<([^>]+)>;\s*rel="next"')
WHEEL_ROLES = ("engine", "host")

Opener = Callable[..., object]


def is_qualifying_astronomer_tag(tag: object) -> bool:
    if not isinstance(tag, str) or not tag.startswith(TAG_PREFIX):
        return False
    return SEMVER_RE.fullmatch(tag[len(TAG_PREFIX):]) is not None


def qualifying_release_tags(releases: object) -> list[str]:
    if not isinstance(releases, list):
        raise ReleaseManifestError("GitHub releases payload must be an array")
    tags: list[str] = []
    for item in releases:
        if not isinstance(item, dict):
            continue
        if item.get("draft") is True or item.get("prerelease") is True:
            continue
        tag = item.get("tag_name")
        if is_qualifying_astronomer_tag(tag):
            assert isinstance(tag, str)
            tags.append(tag)
    return tags


def _wheel_records(manifest: dict[str, object]) -> dict[str, tuple[str, int]]:
    artifacts = manifest["artifacts"]
    if not isinstance(artifacts, dict):
        raise ReleaseManifestError("artifacts must be an object")
    records: dict[str, tuple[str, int]] = {}
    for role in WHEEL_ROLES:
        artifact = artifacts[role]
        if not isinstance(artifact, dict):
            raise ReleaseManifestError(f"artifacts.{role} must be an object")
        filename = artifact["filename"]
        digest = artifact["sha256"]
        size = artifact["bytes"]
        if not isinstance(filename, str) or not isinstance(digest, str):
            raise ReleaseManifestError(f"artifacts.{role} identity is invalid")
        if not isinstance(size, int) or isinstance(size, bool):
            raise ReleaseManifestError(f"artifacts.{role}.bytes must be an integer")
        records[filename] = (digest, size)
    return records


def parse_semver(version: str) -> tuple[int, int, int]:
    match = SEMVER_RE.fullmatch(version)
    if match is None:
        raise ReleaseManifestError(f"invalid semantic version: {version!r}")
    return int(match.group(1)), int(match.group(2)), int(match.group(3))


def check_product_version_monotonicity(
    candidate: dict[str, object],
    priors: Sequence[dict[str, object]],
) -> None:
    """Reject a candidate that is not strictly newer than every published product."""
    raw = candidate.get("version")
    if not isinstance(raw, str):
        raise ReleaseManifestError("candidate version must be a string")
    candidate_tuple = parse_semver(raw)
    for prior in priors:
        prior_version = prior.get("version")
        if not isinstance(prior_version, str):
            raise ReleaseManifestError("published manifest is missing version")
        if candidate_tuple <= parse_semver(prior_version):
            prior_tag = prior.get("tag", prior_version)
            raise ReleaseManifestError(
                f"candidate version {raw} is not strictly greater than published {prior_tag}"
            )


def check_wheel_immutability(
    candidate: dict[str, object],
    priors: Sequence[dict[str, object]],
) -> None:
    """Reject a candidate whose wheel filename collides at a different hash or size."""
    candidate_wheels = _wheel_records(candidate)
    for prior in priors:
        prior_tag = prior.get("tag", "unknown")
        for filename, (digest, size) in _wheel_records(prior).items():
            if filename not in candidate_wheels:
                continue
            candidate_digest, candidate_size = candidate_wheels[filename]
            if candidate_digest != digest:
                raise ReleaseManifestError(
                    f"published wheel {filename} from {prior_tag} changed SHA-256"
                )
            if candidate_size != size:
                raise ReleaseManifestError(
                    f"published wheel {filename} from {prior_tag} changed byte size"
                )


def _artifact(manifest: dict[str, object], role: str) -> dict[str, object]:
    artifacts = manifest["artifacts"]
    if not isinstance(artifacts, dict):
        raise ReleaseManifestError("artifacts must be an object")
    artifact = artifacts[role]
    if not isinstance(artifact, dict):
        raise ReleaseManifestError(f"artifacts.{role} must be an object")
    return artifact


def select_published_wheel(
    *,
    role: str,
    version: str,
    filename: str,
    priors: Sequence[dict[str, object]],
) -> dict[str, object] | None:
    """Return the newest published wheel identity for this role/version/filename.

    Searches every qualifying prior, not only the newest product release, so a
    previously published filename is reused even if a later release shipped a
    different component version. Matching priors must agree on SHA-256 and size.
    """
    if role not in WHEEL_ROLES:
        raise ReleaseManifestError(f"unknown wheel role: {role!r}")
    matches: list[tuple[tuple[int, int, int], str, dict[str, object]]] = []
    for prior in priors:
        artifact = _artifact(prior, role)
        prior_tag = prior.get("tag", "unknown")
        if not isinstance(prior_tag, str):
            prior_tag = "unknown"
        prior_version = artifact.get("version")
        prior_filename = artifact.get("filename")
        same_version = prior_version == version
        same_filename = prior_filename == filename
        if not same_version and not same_filename:
            continue
        if same_version != same_filename:
            raise ReleaseManifestError(
                f"published {prior_tag} artifacts.{role} filename/version mismatch"
            )
        matches.append((parse_semver(str(prior.get("version", "0.0.0"))), prior_tag, artifact))
    if not matches:
        return None
    matches.sort(key=lambda item: item[0])
    _semver, tag, newest = matches[-1]
    digest = newest.get("sha256")
    size = newest.get("bytes")
    for _semver, prior_tag, artifact in matches:
        if artifact.get("sha256") != digest or artifact.get("bytes") != size:
            raise ReleaseManifestError(
                f"published wheel {filename} disagrees between {prior_tag} and {tag}"
            )
    return {
        "tag": tag,
        "role": role,
        "version": version,
        "filename": filename,
        "sha256": digest,
        "bytes": size,
    }


def _urlopen(request: urllib.request.Request, timeout: int = 30):
    return urllib.request.urlopen(request, timeout=timeout)


def _get_json(
    url: str,
    *,
    opener: Opener,
    accept: str = "application/vnd.github+json",
) -> tuple[object, str]:
    request = urllib.request.Request(
        url,
        headers={
            "User-Agent": USER_AGENT,
            "Accept": accept,
        },
    )
    try:
        with opener(request, timeout=30) as response:
            payload = json.loads(response.read().decode("utf-8"))
            link = ""
            headers = getattr(response, "headers", None)
            if headers is not None:
                link = headers.get("Link", "") or headers.get("link", "") or ""
    except (OSError, urllib.error.URLError, json.JSONDecodeError, UnicodeDecodeError) as exc:
        raise ReleaseManifestError(f"cannot fetch {url}: {exc}") from exc
    return payload, link


def require_manifest_matches_release_tag(
    document: object,
    github_tag: str,
) -> dict[str, object]:
    """Bind a downloaded manifest to the GitHub tag it was fetched from."""
    if not is_qualifying_astronomer_tag(github_tag):
        raise ReleaseManifestError(f"not a qualifying Astronomer tag: {github_tag!r}")
    expected_version = github_tag[len(TAG_PREFIX):]
    try:
        manifest = validate_manifest(document)
    except ReleaseManifestError as exc:
        raise ReleaseManifestError(
            f"published {github_tag} {MANIFEST_NAME} is invalid: {exc}"
        ) from exc
    if manifest["tag"] != github_tag or manifest["version"] != expected_version:
        raise ReleaseManifestError(
            f"published {github_tag} {MANIFEST_NAME} identity is "
            f"{manifest['tag']} / {manifest['version']}"
        )
    return manifest


def _refuse_if_offline() -> None:
    if os.environ.get("NO_NETWORK") == "1":
        raise ReleaseManifestError("refusing GitHub fetch because NO_NETWORK=1")


def fetch_published_asset(
    tag: str,
    filename: str,
    *,
    opener: Opener | None = None,
) -> bytes:
    """Download one GitHub Release asset and return its exact bytes."""
    _refuse_if_offline()
    if Path(filename).name != filename or "/" in filename or "\\" in filename:
        raise ReleaseManifestError(f"asset filename must be a basename, not a path: {filename!r}")
    if not is_qualifying_astronomer_tag(tag):
        raise ReleaseManifestError(f"not a qualifying Astronomer tag: {tag!r}")
    download = DOWNLOAD_TEMPLATE.format(tag=tag, filename=filename)
    request = urllib.request.Request(
        download,
        headers={
            "User-Agent": USER_AGENT,
            "Accept": "application/octet-stream",
        },
    )
    open_url = opener or _urlopen
    try:
        with open_url(request, timeout=60) as response:
            payload = response.read()
    except (OSError, urllib.error.URLError) as exc:
        raise ReleaseManifestError(f"cannot fetch {download}: {exc}") from exc
    if not isinstance(payload, (bytes, bytearray)):
        raise ReleaseManifestError(f"cannot fetch {download}: response is not bytes")
    return bytes(payload)


def fetch_published_manifests(*, opener: Opener | None = None) -> list[dict[str, object]]:
    _refuse_if_offline()
    open_url = opener or _urlopen
    tags: list[str] = []
    url: str | None = RELEASES_API
    while url:
        payload, link = _get_json(url, opener=open_url)
        tags.extend(qualifying_release_tags(payload))
        match = NEXT_LINK.search(link)
        url = match.group(1) if match else None

    manifests: list[dict[str, object]] = []
    for tag in tags:
        download = DOWNLOAD_TEMPLATE.format(tag=tag, filename=MANIFEST_NAME)
        payload, _link = _get_json(
            download, opener=open_url, accept="application/json"
        )
        manifests.append(require_manifest_matches_release_tag(payload, tag))
    return manifests
