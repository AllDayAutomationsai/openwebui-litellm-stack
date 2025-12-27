"""
title: Google Sheets Integration
author: assistant
description: Create, read, and modify Google Sheets. Requires OAuth setup with refresh token.
requirements: google-api-python-client, google-auth-oauthlib
version: 1.0.0
license: MIT
"""

import os
import json
from typing import Callable, Awaitable, Any, Optional, List, Dict
from pydantic import BaseModel, Field
from datetime import datetime


class Tools:
    class Valves(BaseModel):
        GOOGLE_CLIENT_ID: str = Field(
            default="",
            description="Google OAuth Client ID from Google Cloud Console"
        )
        GOOGLE_CLIENT_SECRET: str = Field(
            default="",
            description="Google OAuth Client Secret"
        )
        GOOGLE_REFRESH_TOKEN: str = Field(
            default="",
            description="OAuth refresh token (obtained after initial authorization)"
        )

    def __init__(self):
        self.valves = self.Valves()

    def _get_credentials(self):
        """Get Google credentials from refresh token."""
        from google.oauth2.credentials import Credentials
        from google.auth.transport.requests import Request
        
        if not all([
            self.valves.GOOGLE_CLIENT_ID,
            self.valves.GOOGLE_CLIENT_SECRET,
            self.valves.GOOGLE_REFRESH_TOKEN
        ]):
            raise ValueError(
                "Google credentials not configured. Please set GOOGLE_CLIENT_ID, "
                "GOOGLE_CLIENT_SECRET, and GOOGLE_REFRESH_TOKEN in the tool's Valves settings."
            )
        
        creds = Credentials(
            token=None,
            refresh_token=self.valves.GOOGLE_REFRESH_TOKEN,
            token_uri="https://oauth2.googleapis.com/token",
            client_id=self.valves.GOOGLE_CLIENT_ID,
            client_secret=self.valves.GOOGLE_CLIENT_SECRET,
            scopes=[
                "https://www.googleapis.com/auth/spreadsheets",
                "https://www.googleapis.com/auth/drive.file"
            ]
        )
        
        # Refresh the token
        creds.refresh(Request())
        return creds

    async def get_oauth_url(
        self,
        __user__: dict = None,
        __event_emitter__: Callable[[dict], Awaitable[None]] = None,
    ) -> str:
        """
        Get the OAuth authorization URL to obtain a refresh token.
        Use this first if you don't have a refresh token configured.
        
        :return: Instructions with the OAuth URL to authorize the application
        """
        from google_auth_oauthlib.flow import Flow
        
        if not self.valves.GOOGLE_CLIENT_ID or not self.valves.GOOGLE_CLIENT_SECRET:
            return """❌ **Configuration Required**

Please configure the following in the tool's Valves settings:
- `GOOGLE_CLIENT_ID`: Your OAuth Client ID from Google Cloud Console
- `GOOGLE_CLIENT_SECRET`: Your OAuth Client Secret

After configuring, run this tool again to get the authorization URL."""
        
        # Create flow for installed app
        flow = Flow.from_client_config(
            {
                "installed": {
                    "client_id": self.valves.GOOGLE_CLIENT_ID,
                    "client_secret": self.valves.GOOGLE_CLIENT_SECRET,
                    "auth_uri": "https://accounts.google.com/o/oauth2/auth",
                    "token_uri": "https://oauth2.googleapis.com/token",
                }
            },
            scopes=[
                "https://www.googleapis.com/auth/spreadsheets",
                "https://www.googleapis.com/auth/drive.file"
            ],
            redirect_uri="urn:ietf:wg:oauth:2.0:oob"
        )
        
        auth_url, _ = flow.authorization_url(
            access_type='offline',
            include_granted_scopes='true',
            prompt='consent'
        )
        
        return f"""🔐 **Google Sheets OAuth Setup**

**Step 1:** Visit this URL to authorize:
{auth_url}

**Step 2:** After authorizing, you'll receive an authorization code.

**Step 3:** Use the `exchange_auth_code` tool with that code to get your refresh token.

**Step 4:** Add the refresh token to this tool's Valves settings as `GOOGLE_REFRESH_TOKEN`."""

    async def exchange_auth_code(
        self,
        auth_code: str,
        __user__: dict = None,
        __event_emitter__: Callable[[dict], Awaitable[None]] = None,
    ) -> str:
        """
        Exchange an authorization code for a refresh token.
        
        :param auth_code: The authorization code received after OAuth consent
        :return: The refresh token to configure in Valves
        """
        from google_auth_oauthlib.flow import Flow
        
        if not self.valves.GOOGLE_CLIENT_ID or not self.valves.GOOGLE_CLIENT_SECRET:
            return "❌ Please configure GOOGLE_CLIENT_ID and GOOGLE_CLIENT_SECRET first."
        
        flow = Flow.from_client_config(
            {
                "installed": {
                    "client_id": self.valves.GOOGLE_CLIENT_ID,
                    "client_secret": self.valves.GOOGLE_CLIENT_SECRET,
                    "auth_uri": "https://accounts.google.com/o/oauth2/auth",
                    "token_uri": "https://oauth2.googleapis.com/token",
                }
            },
            scopes=[
                "https://www.googleapis.com/auth/spreadsheets",
                "https://www.googleapis.com/auth/drive.file"
            ],
            redirect_uri="urn:ietf:wg:oauth:2.0:oob"
        )
        
        try:
            flow.fetch_token(code=auth_code)
            creds = flow.credentials
            
            return f"""✅ **OAuth Setup Complete!**

**Your Refresh Token:**
```
{creds.refresh_token}
```

⚠️ **Important:** Copy this refresh token and add it to the tool's Valves settings as `GOOGLE_REFRESH_TOKEN`.

After that, you can use all Google Sheets functions!"""
        except Exception as e:
            return f"❌ **Error exchanging code:** {str(e)}"

    async def create_google_sheet(
        self,
        title: str,
        data: Optional[List[List[Any]]] = None,
        __user__: dict = None,
        __event_emitter__: Callable[[dict], Awaitable[None]] = None,
    ) -> str:
        """
        Creates a new Google Sheet with optional initial data.
        
        :param title: The title of the new spreadsheet
        :param data: Optional list of rows to populate the sheet with. Each row is a list of cell values.
        :return: URL to the created Google Sheet
        """
        from googleapiclient.discovery import build
        
        if __event_emitter__:
            await __event_emitter__({
                "type": "status",
                "data": {"description": "Creating Google Sheet...", "done": False}
            })
        
        try:
            creds = self._get_credentials()
        except ValueError as e:
            return str(e)
        except Exception as e:
            return f"❌ **Authentication failed:** {str(e)}\n\nRun `get_oauth_url` to set up OAuth."
        
        try:
            # Create Sheets service
            sheets_service = build('sheets', 'v4', credentials=creds)
            
            # Create the spreadsheet
            spreadsheet = {
                'properties': {'title': title}
            }
            
            result = sheets_service.spreadsheets().create(body=spreadsheet).execute()
            spreadsheet_id = result['spreadsheetId']
            spreadsheet_url = result['spreadsheetUrl']
            
            # Add data if provided
            if data:
                body = {'values': data}
                sheets_service.spreadsheets().values().update(
                    spreadsheetId=spreadsheet_id,
                    range='A1',
                    valueInputOption='RAW',
                    body=body
                ).execute()
            
            if __event_emitter__:
                await __event_emitter__({
                    "type": "status",
                    "data": {"description": "Google Sheet created!", "done": True}
                })
            
            num_rows = len(data) if data else 0
            num_cols = len(data[0]) if data and data[0] else 0
            
            return f"""✅ **Google Sheet created successfully!**

📊 **Title:** {title}
📈 **Data:** {num_rows} rows × {num_cols} columns

🔗 **[Open in Google Sheets]({spreadsheet_url})**

Spreadsheet ID: `{spreadsheet_id}`"""
            
        except Exception as e:
            return f"❌ **Error creating sheet:** {str(e)}"

    async def read_google_sheet(
        self,
        spreadsheet_id: str,
        range_notation: str = "Sheet1",
        __user__: dict = None,
        __event_emitter__: Callable[[dict], Awaitable[None]] = None,
    ) -> str:
        """
        Reads data from an existing Google Sheet.
        
        :param spreadsheet_id: The ID of the spreadsheet (from the URL)
        :param range_notation: The range to read (e.g., 'Sheet1!A1:D10' or just 'Sheet1' for all data)
        :return: The data from the sheet formatted as a table
        """
        from googleapiclient.discovery import build
        
        if __event_emitter__:
            await __event_emitter__({
                "type": "status",
                "data": {"description": "Reading Google Sheet...", "done": False}
            })
        
        try:
            creds = self._get_credentials()
        except ValueError as e:
            return str(e)
        except Exception as e:
            return f"❌ **Authentication failed:** {str(e)}"
        
        try:
            sheets_service = build('sheets', 'v4', credentials=creds)
            
            result = sheets_service.spreadsheets().values().get(
                spreadsheetId=spreadsheet_id,
                range=range_notation
            ).execute()
            
            values = result.get('values', [])
            
            if __event_emitter__:
                await __event_emitter__({
                    "type": "status",
                    "data": {"description": "Data retrieved!", "done": True}
                })
            
            if not values:
                return "📭 **No data found in the specified range.**"
            
            # Format as markdown table
            table_lines = []
            for i, row in enumerate(values):
                table_lines.append("| " + " | ".join(str(cell) for cell in row) + " |")
                if i == 0:
                    table_lines.append("|" + "|".join("---" for _ in row) + "|")
            
            return f"""📊 **Google Sheet Data**

**Range:** {range_notation}
**Rows:** {len(values)}

{chr(10).join(table_lines)}"""
            
        except Exception as e:
            return f"❌ **Error reading sheet:** {str(e)}"

    async def update_google_sheet(
        self,
        spreadsheet_id: str,
        data: List[List[Any]],
        range_notation: str = "A1",
        __user__: dict = None,
        __event_emitter__: Callable[[dict], Awaitable[None]] = None,
    ) -> str:
        """
        Updates data in an existing Google Sheet.
        
        :param spreadsheet_id: The ID of the spreadsheet (from the URL)
        :param data: The data to write as a list of rows
        :param range_notation: The starting cell/range (e.g., 'Sheet1!A1' or just 'A1')
        :return: Confirmation of the update
        """
        from googleapiclient.discovery import build
        
        if __event_emitter__:
            await __event_emitter__({
                "type": "status",
                "data": {"description": "Updating Google Sheet...", "done": False}
            })
        
        try:
            creds = self._get_credentials()
        except ValueError as e:
            return str(e)
        except Exception as e:
            return f"❌ **Authentication failed:** {str(e)}"
        
        try:
            sheets_service = build('sheets', 'v4', credentials=creds)
            
            body = {'values': data}
            result = sheets_service.spreadsheets().values().update(
                spreadsheetId=spreadsheet_id,
                range=range_notation,
                valueInputOption='RAW',
                body=body
            ).execute()
            
            if __event_emitter__:
                await __event_emitter__({
                    "type": "status",
                    "data": {"description": "Sheet updated!", "done": True}
                })
            
            updated_cells = result.get('updatedCells', 0)
            updated_range = result.get('updatedRange', range_notation)
            
            return f"""✅ **Google Sheet updated successfully!**

📝 **Updated range:** {updated_range}
📊 **Cells updated:** {updated_cells}

🔗 **[Open spreadsheet](https://docs.google.com/spreadsheets/d/{spreadsheet_id})**"""
            
        except Exception as e:
            return f"❌ **Error updating sheet:** {str(e)}"
