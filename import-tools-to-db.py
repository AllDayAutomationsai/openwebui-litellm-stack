#!/usr/bin/env python3
"""
Direct database import for OpenWebUI tools.
Run inside the open-webui container to insert tools.
"""

import os
import sys
import json
import time
import uuid
import re
import ast
import psycopg2
from typing import List, Dict, Any

# Database connection
DB_URL = os.environ.get('DATABASE_URL', 'postgresql://openwebui:openwebui_pg_pw_20251221@db:5432/openwebui_db')

# Admin user ID (patrick)
ADMIN_USER_ID = "0d6d69da-b3d5-48bd-97ab-0575f4d0fb03"

# Tools directory
TOOLS_DIR = "/app/custom-tools"


def parse_tool_metadata(content: str) -> dict:
    """Extract metadata from tool file docstring."""
    metadata = {}
    match = re.search(r'"""(.*?)"""', content, re.DOTALL)
    if match:
        docstring = match.group(1)
        for line in docstring.strip().split('\n'):
            if ':' in line:
                key, value = line.split(':', 1)
                metadata[key.strip().lower()] = value.strip()
    return metadata


def extract_function_specs(content: str) -> List[Dict[str, Any]]:
    """Extract function specifications from tool code."""
    specs = []
    
    # Parse the Python code
    try:
        tree = ast.parse(content)
    except:
        return specs
    
    for node in ast.walk(tree):
        if isinstance(node, ast.ClassDef) and node.name == "Tools":
            for item in node.body:
                if isinstance(item, ast.AsyncFunctionDef) or isinstance(item, ast.FunctionDef):
                    if item.name.startswith('_'):
                        continue
                    
                    func_name = item.name
                    docstring = ast.get_docstring(item) or ""
                    
                    # Parse docstring for description and params
                    description = docstring.split('\n')[0] if docstring else func_name
                    
                    # Extract parameters
                    params = {"type": "object", "properties": {}, "required": []}
                    
                    for arg in item.args.args:
                        arg_name = arg.arg
                        if arg_name in ['self', '__user__', '__event_emitter__']:
                            continue
                        
                        # Get type annotation if available
                        param_type = "string"
                        if arg.annotation:
                            ann = ast.unparse(arg.annotation) if hasattr(ast, 'unparse') else str(arg.annotation)
                            if 'List' in ann:
                                param_type = "array"
                            elif 'int' in ann:
                                param_type = "integer"
                            elif 'bool' in ann:
                                param_type = "boolean"
                        
                        # Extract param description from docstring
                        param_desc = ""
                        param_match = re.search(rf':param {arg_name}:\s*(.+?)(?=:param|:return|$)', docstring, re.DOTALL)
                        if param_match:
                            param_desc = param_match.group(1).strip()
                        
                        params["properties"][arg_name] = {
                            "type": param_type,
                            "description": param_desc or f"The {arg_name} parameter"
                        }
                        
                        # Check if required (no default value)
                        defaults_offset = len(item.args.args) - len(item.args.defaults)
                        arg_index = item.args.args.index(arg)
                        if arg_index < defaults_offset:
                            params["required"].append(arg_name)
                    
                    spec = {
                        "name": func_name,
                        "description": description,
                        "parameters": params
                    }
                    specs.append(spec)
    
    return specs


def import_tool(conn, tool_file: str):
    """Import a single tool into the database."""
    with open(tool_file, 'r') as f:
        content = f.read()
    
    metadata = parse_tool_metadata(content)
    specs = extract_function_specs(content)
    
    tool_id = str(uuid.uuid4())
    name = metadata.get('title', os.path.basename(tool_file).replace('.py', ''))
    timestamp = int(time.time())
    
    meta = {
        "description": metadata.get('description', ''),
        "manifest": {
            "version": metadata.get('version', '1.0.0'),
            "author": metadata.get('author', 'system'),
            "license": metadata.get('license', 'MIT')
        }
    }
    
    # Check if tool already exists
    cur = conn.cursor()
    cur.execute("SELECT id FROM tool WHERE name = %s", (name,))
    existing = cur.fetchone()
    
    if existing:
        print(f"  Tool '{name}' already exists, updating...")
        cur.execute("""
            UPDATE tool SET 
                content = %s, 
                specs = %s, 
                meta = %s, 
                updated_at = %s
            WHERE name = %s
        """, (content, json.dumps(specs), json.dumps(meta), timestamp, name))
    else:
        print(f"  Inserting tool '{name}'...")
        cur.execute("""
            INSERT INTO tool (id, user_id, name, content, specs, meta, created_at, updated_at, access_control)
            VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s)
        """, (
            tool_id,
            ADMIN_USER_ID,
            name,
            content,
            json.dumps(specs),
            json.dumps(meta),
            timestamp,
            timestamp,
            json.dumps({"read": {"group_ids": [], "user_ids": []}, "write": {"group_ids": [], "user_ids": []}})
        ))
    
    conn.commit()
    print(f"  ✓ {name} imported successfully")


def main():
    print("=" * 50)
    print("OpenWebUI Tool Importer")
    print("=" * 50)
    
    # Connect to database
    print(f"\nConnecting to database...")
    try:
        conn = psycopg2.connect(DB_URL)
        print("  ✓ Connected")
    except Exception as e:
        print(f"  ✗ Failed to connect: {e}")
        sys.exit(1)
    
    # Import tools
    print(f"\nImporting tools from {TOOLS_DIR}...")
    
    tool_files = [
        os.path.join(TOOLS_DIR, f) 
        for f in os.listdir(TOOLS_DIR) 
        if f.endswith('.py')
    ]
    
    for tool_file in tool_files:
        try:
            import_tool(conn, tool_file)
        except Exception as e:
            print(f"  ✗ Error importing {tool_file}: {e}")
    
    conn.close()
    print("\n" + "=" * 50)
    print("Import complete!")
    print("=" * 50)


if __name__ == "__main__":
    main()
