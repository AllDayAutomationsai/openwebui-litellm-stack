import csv, sqlite3, subprocess, tempfile, os, sys, datetime
SRC = '/root/llm-stack/backups/openwebui_db_20251221_180332.sqlite'
TABLES = [
  'user', 'group', 'group_member', 'folder',
  'chat', 'message', 'message_reaction',
  'api_key', 'auth', 'channel', 'channel_member', 'channel_webhook', 'chatidtag', 'config', 'document', 'feedback', 'file', 'function', 'knowledge', 'knowledge_file', 'memory', 'migratehistory', 'model', 'note', 'oauth_session', 'prompt', 'tag', 'tool'
]
TIMESTAMP_COLS = {
  'config': {'created_at','updated_at'},
  'migratehistory': {'migrated_at'},
}

def to_ts(val):
    if val is None:
        return ''
    if isinstance(val,(int,float)):
        return datetime.datetime.utcfromtimestamp(val).strftime('%Y-%m-%d %H:%M:%S')
    return val

conn = sqlite3.connect(SRC)
conn.row_factory = sqlite3.Row
cur = conn.cursor()

def run_psql(cmd, stdin=None):
    full = ['docker','compose','exec','-T','db','psql','-U','litellmadmin','-d','openwebui_db','-c',cmd]
    res = subprocess.run(full, input=stdin, text=True, capture_output=True)
    if res.returncode != 0:
        sys.stderr.write(res.stderr)
        sys.exit(res.returncode)

run_psql("SET session_replication_role = 'replica';")
for tbl in TABLES:
    cur.execute(f"SELECT * FROM \"{tbl}\"")
    rows = cur.fetchall()
    cols = [d[0] for d in cur.description]
    ts_cols = TIMESTAMP_COLS.get(tbl, set())
    with tempfile.NamedTemporaryFile('w+', newline='', delete=False) as f:
        writer = csv.writer(f)
        writer.writerow(cols)
        for r in rows:
            row_out = []
            for c in cols:
                v = r[c]
                if tbl == 'chat' and c == 'title' and (v is None or v == ''):
                    v = 'Untitled'
                if c in ts_cols:
                    v = to_ts(v)
                row_out.append(v)
            writer.writerow(row_out)
        temp_path = f.name
    run_psql(f'TRUNCATE TABLE "{tbl}" RESTART IDENTITY CASCADE;')
    with open(temp_path,'r') as f:
        copy_cmd = f'COPY "{tbl}" ({", ".join(f"\"{c}\"" for c in cols)}) FROM STDIN WITH (FORMAT csv, HEADER true);'
        full = ['docker','compose','exec','-T','db','psql','-U','litellmadmin','-d','openwebui_db','-c',copy_cmd]
        res = subprocess.run(full, stdin=f, text=True, capture_output=True)
        if res.returncode != 0:
            sys.stderr.write(res.stderr)
            sys.exit(res.returncode)
    os.remove(temp_path)
run_psql("SET session_replication_role = 'origin';")
print('DONE')
