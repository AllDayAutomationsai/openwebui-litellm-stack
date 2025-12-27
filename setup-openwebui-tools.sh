#!/bin/bash
# OpenWebUI Tools Setup Script
# This script imports document generation tools into OpenWebUI

set -e

OPENWEBUI_URL="${OPENWEBUI_URL:-http://localhost:3000}"
TOOLS_DIR="/root/llm-stack/openwebui-tools"

echo "=========================================="
echo "OpenWebUI Document Tools Setup"
echo "=========================================="

# Check if we have an API key/token
if [ -z "$OPENWEBUI_API_KEY" ]; then
    echo ""
    echo "To import tools automatically, you need an API key."
    echo ""
    echo "1. Log into OpenWebUI as admin"
    echo "2. Go to Settings → Account → API Keys"
    echo "3. Create a new API key"
    echo "4. Run: export OPENWEBUI_API_KEY='your-key-here'"
    echo "5. Re-run this script"
    echo ""
    echo "Alternatively, you can manually import tools:"
    echo "  1. Go to Workspace → Tools → Add Tool"
    echo "  2. Copy contents from files in: $TOOLS_DIR"
    echo ""
    exit 1
fi

# Function to import a tool
import_tool() {
    local file=$1
    local name=$(basename "$file" .py)
    
    echo "Importing tool: $name"
    
    # Read the tool content
    local content=$(cat "$file")
    
    # Extract metadata from the tool file
    local title=$(grep -oP '(?<=title: ).*' "$file" | head -1)
    local description=$(grep -oP '(?<=description: ).*' "$file" | head -1)
    
    # Create JSON payload
    local payload=$(jq -n \
        --arg id "$(uuidgen)" \
        --arg name "${title:-$name}" \
        --arg content "$content" \
        --arg meta "{\"description\": \"${description:-Document generation tool}\"}" \
        '{id: $id, name: $name, content: $content, meta: ($meta | fromjson)}')
    
    # Import via API
    response=$(curl -s -X POST "${OPENWEBUI_URL}/api/v1/tools/create" \
        -H "Authorization: Bearer ${OPENWEBUI_API_KEY}" \
        -H "Content-Type: application/json" \
        -d "$payload")
    
    if echo "$response" | grep -q '"id"'; then
        echo "  ✓ Successfully imported: $title"
    else
        echo "  ✗ Failed to import: $title"
        echo "    Response: $response"
    fi
}

# Import all tools
echo ""
echo "Importing tools..."
for tool_file in "$TOOLS_DIR"/*.py; do
    if [ -f "$tool_file" ]; then
        import_tool "$tool_file"
    fi
done

echo ""
echo "=========================================="
echo "Setup Complete!"
echo "=========================================="
echo ""
echo "Next steps for Google Sheets:"
echo "1. Go to Workspace → Tools"
echo "2. Click on 'Google Sheets Integration' tool"
echo "3. Click the gear icon to open Valves"
echo "4. Enter your Google OAuth credentials"
echo "5. Use 'get_oauth_url' function to complete OAuth flow"
echo ""
