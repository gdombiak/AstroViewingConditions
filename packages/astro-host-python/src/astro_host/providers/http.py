"""Provider-neutral single-request HTTP transport."""

from __future__ import annotations

import asyncio
from dataclasses import dataclass
import socket
from typing import Mapping, Protocol
from urllib.error import HTTPError, URLError
from urllib.parse import urlencode
from urllib.request import Request, urlopen

from astro_host.errors import HttpTransportError
from astro_host.models import ProviderFailureKind


@dataclass(frozen=True)
class HttpResponse:
    status: int
    headers: Mapping[str, str]
    body: bytes


class HttpTransport(Protocol):
    async def get(
        self,
        url: str,
        *,
        params: Mapping[str, str],
        timeout_seconds: float,
    ) -> HttpResponse: ...


class UrllibHttpTransport:
    """Stdlib transport. Retry decisions remain in the provider adapter."""

    async def get(
        self,
        url: str,
        *,
        params: Mapping[str, str],
        timeout_seconds: float,
    ) -> HttpResponse:
        target = f"{url}?{urlencode(params)}"
        return await asyncio.to_thread(self._get, target, timeout_seconds)

    @staticmethod
    def _get(target: str, timeout_seconds: float) -> HttpResponse:
        request = Request(target, headers={"User-Agent": "astro-host/0.1"})
        try:
            with urlopen(request, timeout=timeout_seconds) as response:
                return HttpResponse(
                    status=int(response.status),
                    headers=dict(response.headers.items()),
                    body=response.read(),
                )
        except HTTPError as exc:
            return HttpResponse(
                status=int(exc.code),
                headers=dict(exc.headers.items()) if exc.headers else {},
                body=exc.read(),
            )
        except (TimeoutError, socket.timeout) as exc:
            raise HttpTransportError(ProviderFailureKind.TIMEOUT, str(exc)) from exc
        except URLError as exc:
            reason = exc.reason
            kind = (
                ProviderFailureKind.TIMEOUT
                if isinstance(reason, (TimeoutError, socket.timeout))
                else ProviderFailureKind.NETWORK
            )
            raise HttpTransportError(kind, str(reason)) from exc
        except OSError as exc:
            raise HttpTransportError(ProviderFailureKind.NETWORK, str(exc)) from exc
