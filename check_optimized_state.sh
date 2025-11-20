#!/bin/bash
# Health check script for optimized OpenWebUI configuration
# Run this after reboots/updates to verify everything is correct

echo "=========================================="
echo "OpenWebUI Optimized Configuration Check"
echo "=========================================="
echo ""

ISSUES=0

# 1. Check Docker containers
echo "✓ Checking Docker containers..."
RUNNING=$(docker ps --format "{{.Names}}" | sort)
EXPECTED="litellm-db
litellm-prometheus
litellm-proxy
litellm-redis
open-webui
watchtower"

if [ "$RUNNING" == "$EXPECTED" ]; then
    echo "  ✓ All 6 expected containers running"
else
    echo "  ✗ Container mismatch!"
    echo "  Expected: open-webui, litellm-proxy, litellm-db, litellm-redis, litellm-prometheus, watchtower"
    echo "  Running: $(docker ps --format '{{.Names}}' | tr '\n' ' ')"
    ISSUES=$((ISSUES+1))
fi

# 2. Check Ollama is stopped
echo ""
echo "✓ Checking Ollama is stopped..."
if docker ps | grep -q ollama; then
    echo "  ✗ WARNING: Ollama is running but should be stopped!"
    echo "  Run: docker stop ollama"
    ISSUES=$((ISSUES+1))
else
    echo "  ✓ Ollama correctly stopped (not wasting resources)"
fi

# 3. Check Redis caching
echo ""
echo "✓ Checking Redis cache..."
REDIS_PING=$(docker exec litellm-redis redis-cli PING 2>/dev/null)
if [ "$REDIS_PING" == "PONG" ]; then
    CACHE_SIZE=$(docker exec litellm-redis redis-cli DBSIZE | grep -oE '[0-9]+')
    echo "  ✓ Redis responding (cache has $CACHE_SIZE keys)"
else
    echo "  ✗ Redis not responding!"
    ISSUES=$((ISSUES+1))
fi

# 4. Check LiteLLM config has caching enabled
echo ""
echo "✓ Checking LiteLLM caching config..."
if grep -q "cache: true" /root/llm-stack/litellm-config.yaml; then
    echo "  ✓ Redis caching enabled in config"
else
    echo "  ✗ Caching NOT enabled in config!"
    echo "  Restore from: /root/llm-stack/backups/optimized-20251104/litellm-config.yaml"
    ISSUES=$((ISSUES+1))
fi

# 5. Check Nginx running
echo ""
echo "✓ Checking Nginx..."
if systemctl is-active --quiet nginx; then
    echo "  ✓ Nginx running"
    # Check config is valid
    if nginx -t 2>&1 | grep -q "successful"; then
        echo "  ✓ Nginx config valid"
    else
        echo "  ✗ Nginx config has errors!"
        ISSUES=$((ISSUES+1))
    fi
else
    echo "  ✗ Nginx not running!"
    ISSUES=$((ISSUES+1))
fi

# 6. Check Nginx Ollama upstream commented out
echo ""
echo "✓ Checking Nginx Ollama upstream..."
if grep -q "#upstream ollama" /etc/nginx/conf.d/01-upstreams.conf; then
    echo "  ✓ Ollama upstream correctly commented out"
else
    echo "  ✗ Ollama upstream may be active in Nginx!"
    ISSUES=$((ISSUES+1))
fi

# 7. Check LiteLLM API responding
echo ""
echo "✓ Checking LiteLLM API..."
API_TEST=$(curl -s -o /dev/null -w "%{http_code}" -H "Authorization: Bearer sk-Mwo8Vu-yqtdy2yssBiXAtg" http://localhost:4000/models)
if [ "$API_TEST" == "200" ]; then
    echo "  ✓ LiteLLM API responding (HTTP 200)"
else
    echo "  ✗ LiteLLM API not responding correctly (HTTP $API_TEST)"
    ISSUES=$((ISSUES+1))
fi

# 8. Check OpenWebUI accessible
echo ""
echo "✓ Checking OpenWebUI..."
WEBUI_TEST=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:3000)
if [ "$WEBUI_TEST" == "200" ]; then
    echo "  ✓ OpenWebUI responding (HTTP 200)"
    echo "  ✓ Available at: https://pat.solidsuggestions.com"
else
    echo "  ✗ OpenWebUI not responding (HTTP $WEBUI_TEST)"
    ISSUES=$((ISSUES+1))
fi

# 9. Check memory usage
echo ""
echo "✓ Checking memory usage..."
MEMORY_USED=$(free -g | awk '/^Mem:/{print $3}')
echo "  ✓ Memory used: ${MEMORY_USED}GB (should be ~3GB or less)"

# 10. Check monitoring cron removed
echo ""
echo "✓ Checking monitoring cron..."
if crontab -l | grep -q "/root/llm-stack/monitor.sh"; then
    echo "  ✗ LLM monitor still in cron (should be removed)"
    ISSUES=$((ISSUES+1))
else
    echo "  ✓ LLM monitor correctly removed from cron"
fi

# Summary
echo ""
echo "=========================================="
if [ $ISSUES -eq 0 ]; then
    echo "✓ ALL CHECKS PASSED - System optimized!"
else
    echo "✗ FOUND $ISSUES ISSUE(S) - See above for details"
    echo "Consult: /root/llm-stack/PERSIST_CONFIG.md"
fi
echo "=========================================="

exit $ISSUES
