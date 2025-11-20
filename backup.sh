#!/bin/sh
while true; do
    echo "Starting backup at $(date)"
    pg_dump -h litellm-db -U litellmadmin -d litellm_db > /backups/litellm_db_$(date +%Y%m%d_%H%M%S).sql
    find /backups -name '*.sql' -mtime +7 -delete
    echo "Backup completed at $(date)"
    sleep 86400
done
