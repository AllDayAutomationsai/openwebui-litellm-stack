# OpenWebUI Document Generation Tools

## Overview
Your OpenWebUI installation has been enhanced with document generation capabilities:

- **Document Generator** - Creates Word (.docx) files with data URI download
- **Document Generator Pro** - Creates Word/Excel files with native OpenWebUI storage
- **Google Sheets Integration** - Create, read, update Google Sheets

## Persistence
Tools are automatically reinstalled/updated on every container restart via the custom Docker image.

## Files
- `Dockerfile.openwebui` - Custom image with python-docx
- `openwebui-tools/` - Tool source files
- `import-tools-to-db.py` - Database import script
- `startup-wrapper.sh` - Auto-import on startup

## Using the Tools

### Word Documents
In chat, ask your agent to:
- "Create a word document titled 'Report' with content about XYZ"
- "Generate a .docx file summarizing our discussion"

### Excel Spreadsheets
Ask your agent to:
- "Create an Excel spreadsheet with this data: [headers], [row1], [row2]..."
- "Make a spreadsheet comparing X and Y"

### Google Sheets (Requires Setup)
1. Go to [Google Cloud Console](https://console.cloud.google.com/apis/credentials)
2. Create new OAuth credentials
3. Update `/root/llm-stack/.env`:
   ```
   GOOGLE_SHEETS_CLIENT_ID=your_new_client_id
   GOOGLE_SHEETS_CLIENT_SECRET=your_new_secret
   ```
4. In OpenWebUI: Workspace → Tools → Google Sheets Integration → Valves (gear icon)
5. Enter your Client ID and Secret
6. Ask agent: "Get the OAuth URL for Google Sheets"
7. Complete OAuth flow, get refresh token
8. Add refresh token to Valves

## Maintenance
When updating OpenWebUI base image:
```bash
cd /root/llm-stack
docker compose pull
docker compose build open-webui
docker compose up -d open-webui
```
Tools will auto-import after restart.
