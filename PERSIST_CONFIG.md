# OpenWebUI Optimized Configuration - Persistence Guide
**Last Updated:** 2025-11-04
**Location:** pat.solidsuggestions.com

## Current Optimized State

### Active Containers (DO NOT START OLLAMA)
1. **open-webui** - Main OpenWebUI interface (port 3000)
2. **litellm-proxy** - API proxy with Redis caching (port 4000)
3. **litellm-db** - PostgreSQL database
4. **litellm-redis** - Redis cache (enables 30-50% faster repeated queries)
5. **litellm-prometheus** - Metrics monitoring
6. **watchtower** - Auto-updates containers

### Stopped/Disabled Containers
- **ollama** - STOPPED (not used, freed ~600MB RAM)

## Critical Configuration Files

### 1. LiteLLM Config (WITH CACHING ENABLED)
**File:** `/root/llm-stack/litellm-config.yaml`
**Key Settings:**
- Redis caching: `cache: true`
- Cache TTL: `3600` seconds (1 hour)
- Request timeout: `600` seconds
- Max retries: `3`

**Backup Location:** `/root/llm-stack/backups/optimized-20251104/litellm-config.yaml`

### 2. Docker Compose
**File:** `/root/llm-stack/docker-compose.yml`
**Key Settings:**
- All services have `restart: always`
- Ollama service still defined but should remain stopped

**Backup Location:** `/root/llm-stack/backups/optimized-20251104/docker-compose.yml`

### 3. Nginx Configuration
**Files:**
- `/etc/nginx/conf.d/01-upstreams.conf` - Ollama upstream COMMENTED OUT
- `/etc/nginx/conf.d/cache_settings.conf` - keepalive_requests: 1000
- `/etc/nginx/sites-enabled/open-webui.conf` - Main proxy config

**Backup Location:** `/root/nginx-backup-20251104-065656/`

### 4. Cron Jobs
**File:** `/etc/crontab` or `crontab -l`
**Key Settings:**
- LLM monitor script REMOVED (was spamming 401 errors)
- Other system monitors still active

**Backup Location:** `/root/crontab.backup-20251104-065646`

## Startup Sequence

### On System Reboot
1. Docker service starts automatically (systemd)
2. Docker containers with `restart: always` start automatically
3. Nginx starts automatically (systemd)
4. Startup script runs from cron: `/root/start_all_services.sh` (needs update to skip Ollama)

### Manual Start (if needed)
```bash
cd /root/llm-stack
# DO NOT include ollama in the list
docker compose up -d litellm-db litellm-redis litellm-proxy open-webui watchtower litellm-prometheus
```

## Verification Commands

### Check All Services Running (Ollama should NOT be in this list)
```bash
docker ps --format "table {{.Names}}\t{{.Status}}"
```

### Check Ollama is Stopped
```bash
docker ps -a | grep ollama  # Should show "Exited"
```

### Verify Redis Caching Working
```bash
docker exec litellm-redis redis-cli DBSIZE  # Should show growing number of keys
```

### Test LiteLLM API
```bash
curl -H "Authorization: Bearer sk-Mwo8Vu-yqtdy2yssBiXAtg" http://localhost:4000/models
```

### Check Nginx
```bash
systemctl status nginx
nginx -t  # Test configuration
```

## Rollback Instructions

If something breaks after an update/reboot:

### Restore LiteLLM Config
```bash
cp /root/llm-stack/backups/optimized-20251104/litellm-config.yaml /root/llm-stack/litellm-config.yaml
cd /root/llm-stack && docker compose restart litellm-proxy
```

### Restore Nginx Config
```bash
cp -r /root/nginx-backup-20251104-065656/* /etc/nginx/
nginx -t && systemctl reload nginx
```

### Restore Full Docker Stack
```bash
cd /root/llm-stack
docker compose down
docker compose up -d litellm-db litellm-redis litellm-proxy open-webui watchtower litellm-prometheus
# Note: Ollama NOT included
```

## Performance Metrics

### Expected Behavior
- **First query to GPT-5/Gemini:** Normal API latency (5-30s depending on complexity)
- **Repeated identical query:** ~0.1s (served from Redis cache)
- **Memory usage:** ~2.9GB (down from 3.5GB with Ollama stopped)
- **Container count:** 6 running (Ollama stopped)

### Troubleshooting

**If Ollama accidentally starts:**
```bash
docker stop ollama
```

**If caching not working:**
```bash
docker exec litellm-redis redis-cli PING  # Should return PONG
docker logs litellm-proxy | grep -i cache
```

**If OpenWebUI not accessible:**
```bash
systemctl status nginx
docker logs open-webui --tail 50
curl http://localhost:3000  # Should return HTML
```

## Important Notes

1. **Watchtower** auto-updates containers nightly. If it updates and restarts a container, the `restart: always` policy ensures it comes back up with the same config.

2. **Ollama will NOT auto-start** even though it has `restart: always` in docker-compose, because it's explicitly stopped. Docker only auto-restarts containers that were running when Docker daemon stopped.

3. **LiteLLM config is mounted as volume** - changes to `/root/llm-stack/litellm-config.yaml` persist and are loaded on container restart.

4. **Nginx config is on host filesystem** - changes persist across reboots automatically.

5. **Redis data is in Docker volume** - cache survives container restarts but is cleared if container is removed.

## Update Procedures

### When Watchtower Auto-Updates Containers
- Containers restart with same config automatically
- No action needed

### Manual Container Update
```bash
cd /root/llm-stack
docker compose pull <container-name>
docker compose up -d <container-name>
```

### Nginx Update (via apt)
```bash
# Nginx config persists automatically
apt update && apt upgrade nginx
systemctl reload nginx
```

### System Reboot
```bash
# Everything auto-starts via systemd and docker restart policies
reboot
# After reboot, verify with: docker ps
```
