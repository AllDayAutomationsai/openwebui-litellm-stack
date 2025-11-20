# OpenWebUI Quick Reference Guide
**Location:** pat.solidsuggestions.com
**Last Updated:** 2025-11-04

## Quick Status Check
```bash
/root/llm-stack/check_optimized_state.sh
```
This script verifies everything is running correctly.

## After Reboot/Update - Verify Everything
```bash
# 1. Quick health check
/root/llm-stack/check_optimized_state.sh

# 2. If all checks pass, you're good!
# 3. If issues found, see /root/llm-stack/PERSIST_CONFIG.md
```

## What Should Be Running
✅ **6 containers:**
- open-webui (main UI)
- litellm-proxy (API proxy with caching)
- litellm-db (database)
- litellm-redis (cache - enables 30-50% faster responses)
- litellm-prometheus (metrics)
- watchtower (auto-updates)

❌ **Ollama should NOT be running** (wastes ~600MB RAM)

## Common Commands

### Check what's running
```bash
docker ps --format "table {{.Names}}\t{{.Status}}"
```

### View logs
```bash
docker logs open-webui --tail 50
docker logs litellm-proxy --tail 50
```

### Restart a service
```bash
docker restart litellm-proxy
# or
cd /root/llm-stack && docker compose restart litellm-proxy
```

### Check Redis cache is working
```bash
docker exec litellm-redis redis-cli DBSIZE  # Shows number of cached queries
```

### Stop Ollama if it accidentally starts
```bash
docker stop ollama
```

## If Something Breaks

### Full restart
```bash
cd /root/llm-stack
docker compose restart
docker stop ollama  # Make sure Ollama stays stopped
```

### Restore optimized config
```bash
# LiteLLM config
cp /root/llm-stack/backups/optimized-20251104/litellm-config.yaml /root/llm-stack/litellm-config.yaml
docker compose restart litellm-proxy

# Nginx config
cp -r /root/nginx-backup-20251104-065656/* /etc/nginx/
systemctl reload nginx
```

## Performance Features Enabled

✅ **Redis Caching** - Repeated queries are 30-50% faster
✅ **Optimized Nginx** - Better connection handling
✅ **No Ollama overhead** - ~600MB RAM freed
✅ **Clean logs** - No monitoring script spam

## Test Caching

1. Go to https://pat.solidsuggestions.com
2. Ask: "What is 2+2?"
3. Wait for response
4. Ask the EXACT same question again
5. Second response should be ~instant (from cache)

## Auto-Start Configuration

✅ Docker service: Enabled (starts on boot)
✅ Nginx service: Enabled (starts on boot)
✅ Containers: `restart: always` (except Ollama)
✅ Startup script: `/root/start_all_services.sh` (runs on boot)

Everything will automatically start correctly after:
- System reboots
- Docker daemon restarts
- Container updates (via Watchtower)

## Documentation Files

- **This file:** Quick reference
- `/root/llm-stack/PERSIST_CONFIG.md` - Full configuration details
- `/root/llm-stack/check_optimized_state.sh` - Health check script
- `/root/start_all_services.sh` - Boot startup script

## Need Help?

Run the health check first:
```bash
/root/llm-stack/check_optimized_state.sh
```

It will tell you exactly what's wrong and how to fix it.
