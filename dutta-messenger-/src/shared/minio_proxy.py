"""Reverse-proxy MinIO object requests through the main FastAPI app.

Why this exists
---------------
On demo/dev deploys we expose the API via a single ngrok tunnel. MinIO
sits on `localhost:9000` and is not publicly reachable, so the presigned
PUT URLs it returns (with host=localhost:9000) fail from physical phones
on mobile networks — the phone simply cannot resolve/route to localhost.

The fix: have boto3 sign URLs against the *public* API hostname
(`MINIO_URL=https://<ngrok-host>`), then have this proxy catch the
bucket-prefixed path here at the API edge and forward the request
verbatim to MinIO at 127.0.0.1:9000, preserving the `Host` header so
MinIO's SigV4 validator still sees the exact host the URL was signed
against. The signature remains intact and the object is stored.

Scope
-----
Only enabled when `STORAGE_TYPE=minio`. Only forwards requests whose
first path segment equals `settings.MINIO_BUCKET`. Anything else 404s.

Streaming: both request and response bodies are streamed to avoid
buffering large media uploads/downloads in memory.
"""

from __future__ import annotations

import httpx
import structlog
from fastapi import APIRouter, HTTPException, Request
from fastapi.responses import StreamingResponse

from src.config import settings

logger = structlog.get_logger()


router = APIRouter(tags=["_internal"], include_in_schema=False)


# Headers that are hop-by-hop or set by the proxy itself. Strip before
# forwarding upstream + before returning downstream.
#
# `content-length` is intentionally NOT stripped on the upstream forward:
# MinIO rejects chunked uploads with `MissingContentLength`, so we need
# the client's Content-Length to reach it verbatim. httpx will honor the
# explicit header when passed alongside a streaming body.
_HOP_BY_HOP = {
    "connection",
    "keep-alive",
    "proxy-authenticate",
    "proxy-authorization",
    "te",
    "trailers",
    "transfer-encoding",
    "upgrade",
}

# Headers that must NOT flow back to the downstream client. The Starlette
# StreamingResponse computes its own content-length when possible, and
# leaving MinIO's upstream content-length in place confuses the runtime.
_RESPONSE_STRIP = _HOP_BY_HOP | {"content-length"}


def _minio_upstream() -> str:
    """Physical address of the MinIO server on the box running this app."""
    return "http://127.0.0.1:9000"


def _public_host() -> str | None:
    """Public hostname the signed URL uses. Forwarded as the upstream
    `Host` header so MinIO's signature validator sees exactly what boto3
    signed against.

    Derived from `MINIO_URL` which we set to the ngrok public URL.
    """
    try:
        return httpx.URL(settings.MINIO_URL).host
    except Exception:
        return None


# Use a single reusable client — httpx keeps a connection pool for us.
_client = httpx.AsyncClient(
    base_url=_minio_upstream(),
    timeout=httpx.Timeout(connect=5.0, read=300.0, write=300.0, pool=5.0),
    follow_redirects=False,
)


@router.api_route(
    "/" + settings.MINIO_BUCKET + "/{key:path}",
    methods=["GET", "PUT", "HEAD", "POST", "DELETE"],
)
async def minio_proxy(key: str, request: Request) -> StreamingResponse:
    """Forward a signed S3 request to the local MinIO instance.

    The incoming request has already been path-routed to `/<bucket>/<key>`
    with a SigV4 query-string signature generated against the public
    ngrok host. We replay it to MinIO preserving method, query, body, and
    the original `Host` header so the signature matches on the far side.
    """
    if settings.STORAGE_TYPE.lower() != "minio":
        raise HTTPException(status_code=404, detail="Not found")

    upstream_path = f"/{settings.MINIO_BUCKET}/{key}"
    upstream_host = _public_host()

    # Rebuild headers: drop hop-by-hop and override Host to the public
    # hostname that boto3 used when computing the signature. If we can't
    # determine the public host, fall back to the incoming Host header —
    # which at least carries the right value when the request came in
    # through ngrok.
    forwarded_headers: dict[str, str] = {}
    for name, value in request.headers.items():
        if name.lower() in _HOP_BY_HOP:
            continue
        if name.lower() == "host":
            continue
        forwarded_headers[name] = value
    forwarded_headers["host"] = upstream_host or request.headers.get("host", "")

    # Stream the body. `request.stream()` yields bytes as they arrive,
    # avoiding a full in-memory buffer for multi-MB uploads.
    body_iter = request.stream()

    try:
        upstream_req = _client.build_request(
            method=request.method,
            url=upstream_path,
            params=request.query_params,
            headers=forwarded_headers,
            content=body_iter,
        )
        upstream_resp = await _client.send(upstream_req, stream=True)
    except httpx.HTTPError as exc:
        logger.error("minio_proxy_upstream_error", error=str(exc), key=key)
        raise HTTPException(status_code=502, detail="MinIO upstream unreachable") from exc

    # Build the downstream response. Strip hop-by-hop headers so the
    # client's HTTP stack doesn't get confused by e.g. connection:close.
    response_headers = {
        name: value
        for name, value in upstream_resp.headers.items()
        if name.lower() not in _RESPONSE_STRIP
    }

    async def _iter_body():
        try:
            async for chunk in upstream_resp.aiter_raw():
                yield chunk
        finally:
            await upstream_resp.aclose()

    return StreamingResponse(
        _iter_body(),
        status_code=upstream_resp.status_code,
        headers=response_headers,
        media_type=upstream_resp.headers.get("content-type"),
    )


__all__ = ["router"]
