#!/bin/bash
set -e

# Import tools in background after startup
(
    # Wait for the web server to be ready
    echo "Waiting for OpenWebUI to start..."
    for i in {1..60}; do
        if curl -s http://localhost:8080/api/health > /dev/null 2>&1; then
            echo "OpenWebUI is ready, importing tools..."
            python /app/import-tools-to-db.py 2>&1 || echo "Tool import completed (may have had warnings)"
            break
        fi
        sleep 2
    done
) &

# Run the original start script
exec /app/backend/start.sh "$@"
