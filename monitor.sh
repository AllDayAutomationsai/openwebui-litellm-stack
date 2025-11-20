#!/bin/bash
# Health monitoring and auto-recovery script for LLM stack

LOG_FILE="/root/llm-stack/monitor.log"
MAX_LOG_SIZE=10485760  # 10MB

# Rotate log if it gets too large
if [ -f "$LOG_FILE" ] && [ $(stat -c%s "$LOG_FILE") -gt $MAX_LOG_SIZE ]; then
    mv "$LOG_FILE" "$LOG_FILE.old"
fi

log_msg() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}

check_service() {
    local service=$1
    local status=$(docker inspect -f '{{.State.Status}}' "$service" 2>/dev/null)
    local health=$(docker inspect -f '{{.State.Health.Status}}' "$service" 2>/dev/null)
    
    if [ "$status" != "running" ]; then
        return 1
    fi
    
    if [ "$health" != "" ] && [ "$health" != "healthy" ] && [ "$health" != "{{.State.Health.Status}}" ]; then
        return 2
    fi
    
    return 0
}

recover_stack() {
    log_msg "RECOVERY: Attempting to recover LLM stack"
    
    cd /root/llm-stack
    
    # Start services in order
    docker compose up -d litellm-db
    sleep 10
    
    docker compose up -d litellm-redis ollama
    sleep 10
    
    docker compose up -d litellm-proxy
    sleep 20
    
    docker compose up -d open-webui
    sleep 10
    
    docker compose up -d
    
    log_msg "RECOVERY: Recovery attempt completed"
}

# Main monitoring loop
log_msg "Monitor started"

FAILURE_COUNT=0
MAX_FAILURES=3

for service in litellm-db litellm-redis ollama litellm-proxy open-webui; do
    check_service "$service"
    result=$?
    
    if [ $result -eq 1 ]; then
        log_msg "ERROR: $service is not running"
        FAILURE_COUNT=$((FAILURE_COUNT + 1))
    elif [ $result -eq 2 ]; then
        log_msg "WARNING: $service is unhealthy"
        FAILURE_COUNT=$((FAILURE_COUNT + 1))
    else
        log_msg "OK: $service is healthy"
    fi
done

# Check if LiteLLM can list models
if curl -s -f http://localhost:4000/models > /dev/null 2>&1; then
    log_msg "OK: LiteLLM API responding with models"
else
    log_msg "ERROR: LiteLLM API not responding or no models"
    FAILURE_COUNT=$((FAILURE_COUNT + 1))
fi

if [ $FAILURE_COUNT -gt 0 ]; then
    log_msg "ALERT: $FAILURE_COUNT failures detected"
    
    if [ $FAILURE_COUNT -ge $MAX_FAILURES ]; then
        recover_stack
    fi
fi

log_msg "Monitor check completed (failures: $FAILURE_COUNT)"
