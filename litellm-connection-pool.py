import os
os.environ["LITELLM_PERSISTENT_CONNECTIONS"] = "true"
os.environ["LITELLM_CONNECTION_POOL_SIZE"] = "20"
os.environ["LITELLM_CONNECTION_TIMEOUT"] = "300"
os.environ["LITELLM_MAX_KEEPALIVE_CONNECTIONS"] = "10"
os.environ["HTTPX_HTTP2"] = "1"

# Monkey patch for persistent connections
import litellm
from litellm import completion
import httpx
import aiohttp
from functools import wraps

# Create persistent client with connection pooling
http_client = httpx.AsyncClient(
    http2=True,
    limits=httpx.Limits(
        max_keepalive_connections=10,
        max_connections=20,
        keepalive_expiry=300.0
    ),
    timeout=httpx.Timeout(60.0, connect=5.0)
)

# Override LiteLLM's HTTP client
litellm.client = http_client
litellm.aclient = http_client

print("✓ Persistent HTTP/2 connections enabled")
