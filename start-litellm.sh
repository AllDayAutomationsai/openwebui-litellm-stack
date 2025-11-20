#!/bin/bash
# Optimized LiteLLM startup with parallel processing

# Python async optimization
export PYTHONUNBUFFERED=1
export PYTHONASYNCIODEBUG=0
export UV_THREADPOOL_SIZE=16

# LiteLLM parallel settings
export LITELLM_PARALLELISM=100
export LITELLM_REQUEST_TIMEOUT=600
export LITELLM_THREAD_POOL_SIZE=8
export LITELLM_CONNECTION_POOL_SIZE=100

# Use uvloop for better async performance
pip install uvloop aiohttp[speedups] orjson 2>/dev/null

# Start with Gunicorn + Uvicorn workers for parallel processing
exec gunicorn litellm.proxy.proxy_server:app \
  --workers 4 \
  --worker-class uvicorn.workers.UvicornWorker \
  --bind 0.0.0.0:4000 \
  --timeout 600 \
  --keep-alive 75 \
  --worker-connections 1000 \
  --max-requests 1000 \
  --max-requests-jitter 50 \
  --access-logfile - \
  --error-logfile - \
  --log-level info
