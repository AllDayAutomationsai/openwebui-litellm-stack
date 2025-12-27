#!/usr/bin/env bash
#
# Robust auto-update script for LLM stack
# - Backs up both PostgreSQL databases (litellm_db + openwebui_db)
# - Only restarts containers when images have actually changed
# - Preserves model visibility settings across updates
# - Ensures OpenWebUI config has correct LiteLLM URL (/v1 suffix)
# - Health checks after restart with rollback on failure
# - Cleans up old backups (keeps last 7 days)
#

set -euo pipefail

BASE="/root/llm-stack"
TS_DATE=$(date +%Y%m%d)
TS_TIME=$(date +%H%M%S)
BACKUP_DIR="$BASE/backups/${TS_DATE}/${TS_TIME}"
LOGFILE="$BASE/logs/auto-update.log"
HEALTH_TIMEOUT=120
KEEP_BACKUPS_DAYS=7

ALERT_EMAIL="patrick@consultingcct.com"

# Load environment variables
if [ -f "$BASE/.env" ]; then
    set -a
    source "$BASE/.env"
    set +a
fi

# Use LITELLM_MASTER_KEY from env, fallback to empty
LITELLM_API_KEY="${LITELLM_MASTER_KEY:-}"

send_alert() {
    local subject="$1"
    local body="$2"
    {
        echo "Subject: [LLM-STACK] $subject"
        echo "From: root@$(hostname)"
        echo "To: $ALERT_EMAIL"
        echo ""
        echo "$body"
        echo ""
        echo "--- Recent log ---"
        tail -30 "$LOGFILE"
    } | sendmail -t
}

log() {
    echo "[$(date --iso-8601=seconds)] $1" | tee -a "$LOGFILE"
}

cleanup_old_backups() {
    log "Cleaning up backups older than $KEEP_BACKUPS_DAYS days..."
    find "$BASE/backups" -mindepth 1 -maxdepth 1 -type d -mtime +$KEEP_BACKUPS_DAYS -exec rm -rf {} \; 2>/dev/null || true
}

wait_for_healthy() {
    local container=$1
    local timeout=$2
    local elapsed=0

    log "Waiting for $container to be healthy..."

    while [ $elapsed -lt $timeout ]; do
        status=$(docker inspect --format='{{.State.Health.Status}}' "$container" 2>/dev/null || echo "no-healthcheck")

        if [ "$status" = "healthy" ]; then
            log "$container is healthy"
            return 0
        elif [ "$status" = "no-healthcheck" ]; then
            if docker ps --format '{{.Names}}' | grep -q "^${container}$"; then
                log "$container is running (no healthcheck defined)"
                return 0
            fi
        fi

        sleep 5
        elapsed=$((elapsed + 5))
    done

    log "ERROR: $container failed to become healthy within ${timeout}s"
    return 1
}

save_model_states() {
    log "Saving model visibility states..."
    docker exec litellm-db psql -U openwebui -d openwebui_db -t -A -c \
        "SELECT id || '|' || is_active FROM model;" > "$BACKUP_DIR/model_states.txt" 2>/dev/null || true

    if [ -s "$BACKUP_DIR/model_states.txt" ]; then
        local count=$(wc -l < "$BACKUP_DIR/model_states.txt")
        log "Saved $count model states"
    else
        log "WARNING: Could not save model states"
    fi
}

restore_model_states() {
    log "Restoring model visibility states..."

    if [ ! -f "$BACKUP_DIR/model_states.txt" ]; then
        log "WARNING: No model states backup found"
        return 0
    fi

    if ! wait_for_healthy "litellm-db" 60; then
        log "ERROR: Database not ready for model state restore"
        return 1
    fi

    sleep 10

    local restored=0
    while IFS='|' read -r model_id is_active; do
        if [ -n "$model_id" ]; then
            docker exec litellm-db psql -U openwebui -d openwebui_db -c \
                "UPDATE model SET is_active = $is_active WHERE id = '$model_id';" >/dev/null 2>&1 && \
                restored=$((restored + 1)) || true
        fi
    done < "$BACKUP_DIR/model_states.txt"

    log "Restored $restored model visibility states"
}

# Returns 0 if config was changed, 1 if no changes needed
fix_openwebui_config() {
    log "Checking OpenWebUI config for correct LiteLLM URL..."

    if ! wait_for_healthy "litellm-db" 30; then
        log "WARNING: Database not ready, skipping config fix"
        return 1
    fi

    # Fix LiteLLM URL to ensure /v1 suffix
    # Returns exit code 0 if modified, 1 if no changes
    python3 << 'PYEOF'
import subprocess
import json
import sys

try:
    result = subprocess.run([
        'docker', 'exec', 'litellm-db', 'psql', '-U', 'openwebui', '-d', 'openwebui_db',
        '-t', '-A', '-c', 'SELECT data FROM config ORDER BY id DESC LIMIT 1;'
    ], capture_output=True, text=True, timeout=30)

    if result.returncode != 0 or not result.stdout.strip():
        print("No config found or error reading")
        sys.exit(1)

    data = json.loads(result.stdout.strip())
    modified = False

    # Fix openai api_base_urls
    if 'openai' in data and 'api_base_urls' in data['openai']:
        urls = data['openai']['api_base_urls']
        fixed_urls = []
        for url in urls:
            if 'litellm-proxy:4000' in url and not url.rstrip('/').endswith('/v1'):
                fixed_url = url.rstrip('/') + '/v1'
                fixed_urls.append(fixed_url)
                print(f"Fixed URL: {url} -> {fixed_url}")
                modified = True
            else:
                fixed_urls.append(url)
        data['openai']['api_base_urls'] = fixed_urls

    if modified:
        json_str = json.dumps(data).replace("'", "''")
        update_sql = f"UPDATE config SET data = '{json_str}'::json, updated_at = now() WHERE id = (SELECT id FROM config ORDER BY id DESC LIMIT 1);"
        subprocess.run([
            'docker', 'exec', 'litellm-db', 'psql', '-U', 'openwebui', '-d', 'openwebui_db', '-c', update_sql
        ], capture_output=True, timeout=30)
        print("Config updated successfully")
        sys.exit(0)  # Modified
    else:
        print("Config OK, no changes needed")
        sys.exit(1)  # Not modified

except Exception as e:
    print(f"Error: {e}")
    sys.exit(1)
PYEOF
}

perform_backup() {
    log "Creating backup directory: $BACKUP_DIR"
    mkdir -p "$BACKUP_DIR" "$BASE/logs"

    if ! wait_for_healthy "litellm-db" 30; then
        log "ERROR: Database not healthy, cannot backup"
        return 1
    fi

    log "Backing up litellm_db..."
    if docker exec litellm-db pg_dump -U litellmadmin litellm_db > "$BACKUP_DIR/litellm_db.sql" 2>/dev/null; then
        log "litellm_db backup complete"
    else
        log "WARNING: litellm_db backup failed"
    fi

    log "Backing up openwebui_db..."
    if docker exec litellm-db pg_dump -U openwebui openwebui_db > "$BACKUP_DIR/openwebui_db.sql" 2>/dev/null; then
        log "openwebui_db backup complete"
    else
        log "WARNING: openwebui_db backup failed"
    fi

    save_model_states

    log "Backing up config files..."
    cp "$BASE/docker-compose.yml" "$BACKUP_DIR/docker-compose.yml"
    cp "$BASE/litellm-config.yaml" "$BACKUP_DIR/litellm-config.yaml"
    [ -f "$BASE/.env" ] && cp "$BASE/.env" "$BACKUP_DIR/.env"
    [ -f "$BASE/docker-compose.override.yml" ] && cp "$BASE/docker-compose.override.yml" "$BACKUP_DIR/docker-compose.override.yml"

    log "Backup completed at $BACKUP_DIR"
    return 0
}

# Check if any images have updates available
# Returns 0 if updates available, 1 if no updates
check_for_updates() {
    log "Checking for image updates..."
    cd "$BASE"

    # Capture pull output
    local pull_output
    pull_output=$(docker compose pull 2>&1)
    echo "$pull_output" | tee -a "$LOGFILE"

    # Check if any images were actually downloaded
    # "Downloaded" or "Pull complete" or "Downloaded newer image" indicates new content
    if echo "$pull_output" | grep -qiE "(Downloaded|Pull complete|Downloaded newer)"; then
        log "New images available"
        return 0
    else
        log "All images up to date, no restart needed"
        return 1
    fi
}

perform_update() {
    log "Stopping containers gracefully..."
    cd "$BASE"
    docker compose stop open-webui 2>&1 | tee -a "$LOGFILE" || true
    docker compose stop litellm-proxy 2>&1 | tee -a "$LOGFILE" || true
    docker compose stop ollama litellm-redis litellm-prometheus 2>&1 | tee -a "$LOGFILE" || true

    log "Starting containers with new images..."
    docker compose up -d 2>&1 | tee -a "$LOGFILE"

    return 0
}

verify_health() {
    log "Verifying container health..."
    local failed=0

    for container in litellm-db ollama litellm-redis litellm-proxy open-webui; do
        if ! wait_for_healthy "$container" "$HEALTH_TIMEOUT"; then
            failed=1
        fi
    done

    if [ $failed -eq 1 ]; then
        log "ERROR: Some containers failed health checks"
        return 1
    fi

    log "All containers healthy"
    return 0
}

verify_models_accessible() {
    log "Verifying models are accessible..."

    if [ -z "$LITELLM_API_KEY" ]; then
        log "WARNING: LITELLM_MASTER_KEY not set, skipping model verification"
        return 0
    fi

    # Test that LiteLLM returns models
    local model_count=$(docker exec open-webui curl -s http://litellm-proxy:4000/v1/models \
        -H "Authorization: Bearer $LITELLM_API_KEY" 2>/dev/null | \
        python3 -c "import sys,json; print(len(json.load(sys.stdin).get('data',[])))" 2>/dev/null || echo "0")

    if [ "$model_count" -gt 0 ]; then
        log "LiteLLM serving $model_count models"
        return 0
    else
        log "WARNING: LiteLLM not returning models"
        return 1
    fi
}

rollback() {
    local backup_path=$1
    log "ROLLBACK: Attempting to restore from $backup_path"

    cd "$BASE"

    [ -f "$backup_path/docker-compose.yml" ] && cp "$backup_path/docker-compose.yml" "$BASE/docker-compose.yml"
    [ -f "$backup_path/litellm-config.yaml" ] && cp "$backup_path/litellm-config.yaml" "$BASE/litellm-config.yaml"
    [ -f "$backup_path/.env" ] && cp "$backup_path/.env" "$BASE/.env"

    docker compose down 2>&1 | tee -a "$LOGFILE" || true
    docker compose up -d 2>&1 | tee -a "$LOGFILE"

    log "ROLLBACK: Config files restored, containers restarted"
}

main() {
    log "=========================================="
    log "Starting auto-update process"

    cleanup_old_backups

    # Always perform backup (daily DB backup)
    if ! perform_backup; then
        log "ERROR: Backup failed"
        send_alert "Backup FAILED" "Could not create daily backup."
        exit 1
    fi

    # Check for updates - only restart if new images available
    if check_for_updates; then
        log "Updates found, proceeding with restart..."

        if ! perform_update; then
            log "ERROR: Update failed, attempting rollback"
            rollback "$BACKUP_DIR"
            exit 1
        fi

        if ! verify_health; then
            log "ERROR: Health check failed, attempting rollback"
            send_alert "Update FAILED - Rolled back" "Health check failed after update. System has been rolled back to previous state."
            rollback "$BACKUP_DIR"
            exit 1
        fi

        # Only restore model states if we actually restarted
        restore_model_states

        # Check and fix config, only restart OpenWebUI if config was changed
        if fix_openwebui_config; then
            log "Config was fixed, restarting OpenWebUI to apply..."
            docker restart open-webui 2>&1 | tee -a "$LOGFILE" || true
            sleep 15
        fi

        # Final verification
        if ! verify_models_accessible; then
            log "WARNING: Models may not be accessible, check manually"
        fi

        log "Pruning unused images..."
        docker image prune -f 2>&1 | tee -a "$LOGFILE" || true

        log "Auto-update completed with container restart"
    else
        log "No updates found, skipping container restart"
        log "Daily backup completed successfully"
    fi

    log "=========================================="
}

main "$@"
