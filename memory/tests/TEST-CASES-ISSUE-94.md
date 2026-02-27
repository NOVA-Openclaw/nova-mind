# Test Cases — Issue #94: Centralized database config file

**Issue:** nova-memory #94  
**Feature:** `~/.openclaw/postgres.json` with ENV fallback  
**Resolution order:** ENV vars → postgres.json → hardcoded defaults  
**Author:** Gem (QA Engineer)  
**Date:** 2026-02-16  

---

## 1. Loader Functions — Happy Path

### TC-1.1: Config file with all fields, no ENV vars
**Applies to:** bash, python, TypeScript loaders  
**Setup:** `~/.openclaw/postgres.json` with all 5 fields populated; no `PG*` env vars set  
**Action:** Call `load_pg_env()`  
**Expected:** `PGHOST`, `PGPORT`, `PGDATABASE`, `PGUSER`, `PGPASSWORD` all set from JSON values  

### TC-1.2: All ENV vars set, config file exists
**Setup:** All 5 `PG*` env vars set; config file exists with different values  
**Action:** Call `load_pg_env()`  
**Expected:** All env vars retain their original values; config file values ignored  

### TC-1.3: All ENV vars set, no config file
**Setup:** All 5 `PG*` env vars set; no config file  
**Action:** Call `load_pg_env()`  
**Expected:** All env vars retain their original values; no error  

### TC-1.4: Mixed — some ENV vars, rest from config
**Setup:** `PGHOST=remotehost` and `PGPORT=9999` set; config file has all 5 fields  
**Action:** Call `load_pg_env()`  
**Expected:** `PGHOST=remotehost`, `PGPORT=9999` (from ENV); `PGDATABASE`, `PGUSER`, `PGPASSWORD` from config  

---

## 2. Loader Functions — Defaults

### TC-2.1: No ENV vars, no config file
**Setup:** No `PG*` env vars; no config file  
**Action:** Call `load_pg_env()`  
**Expected:** `PGHOST=localhost`, `PGPORT=5432`, `PGUSER=$(whoami)`. `PGDATABASE` and `PGPASSWORD` remain unset.  

### TC-2.2: Config file with only some fields
**Setup:** Config file: `{"host": "dbserver", "port": 5433}`. No ENV vars.  
**Action:** Call `load_pg_env()`  
**Expected:** `PGHOST=dbserver`, `PGPORT=5433` (from config); `PGUSER=$(whoami)` (default); `PGDATABASE`/`PGPASSWORD` unset  

### TC-2.3: Config file with empty values
**Setup:** Config file: `{"host": "", "port": 5432, "user": ""}`. No ENV vars.  
**Action:** Call `load_pg_env()`  
**Expected:** Bash uses `// empty` so empty strings are treated as missing → defaults apply for `host` and `user`. `PGHOST=localhost`, `PGUSER=$(whoami)`. Python/TS: verify empty string handling — empty string should not override defaults.  

---

## 3. Loader Functions — Edge Cases

### TC-3.1: Config file has extra/unknown fields
**Setup:** Config file: `{"host": "db", "port": 5432, "sslmode": "require", "extra": true}`  
**Action:** Call `load_pg_env()`  
**Expected:** Known fields mapped correctly; unknown fields ignored; no error  

### TC-3.2: Port as string in JSON
**Setup:** Config file: `{"port": "5433"}`  
**Action:** Call `load_pg_env()`  
**Expected:** `PGPORT=5433` (env vars are strings — should coerce cleanly)  

### TC-3.3: Port as integer in JSON
**Setup:** Config file: `{"port": 5433}`  
**Action:** Call `load_pg_env()`  
**Expected:** `PGPORT=5433` (TypeScript/Python use `String()`/`str()` conversion)  

### TC-3.4: Null values in JSON
**Setup:** Config file: `{"host": null, "port": 5432}`  
**Action:** Call `load_pg_env()`  
**Expected:** `host` treated as missing; `PGHOST=localhost` (default). Bash: `jq -r '.host // empty'` returns empty for null. Python: `None` → skipped (`json_key in cfg` is true but value is None — verify). TypeScript: `cfg[jsonKey] != null` → skipped correctly.  

### TC-3.5: ENV var set to empty string
**Setup:** `PGHOST=""` exported; config file has `"host": "dbserver"`  
**Action:** Call `load_pg_env()`  
**Expected:** Bash `${PGHOST:-...}` treats empty as unset → uses config value. Python `os.environ.get("PGHOST")` returns `""` which is truthy in the `not` check → depends on implementation (empty string = falsy in Python, so config would be used). Document expected behavior per language.  

---

## 4. Error Conditions

### TC-4.1: Malformed JSON in config file
**Setup:** Config file contains `{invalid json`  
**Action:** Call `load_pg_env()`  
**Expected:** Bash: `jq` fails silently per field, defaults apply. Python: `json.load()` raises `JSONDecodeError` — should be caught; fall through to defaults. TypeScript: `JSON.parse()` throws — should be caught; fall through to defaults.  
**Note:** Loaders MUST NOT crash on bad JSON. Verify graceful degradation.  

### TC-4.2: Config file is not readable (permissions 000)
**Setup:** Config file exists but `chmod 000`  
**Action:** Call `load_pg_env()`  
**Expected:** File read fails; defaults apply; no crash  

### TC-4.3: Config file is a directory
**Setup:** `~/.openclaw/postgres.json` is a directory  
**Action:** Call `load_pg_env()`  
**Expected:** Read fails gracefully; defaults apply  

### TC-4.4: `~/.openclaw/` directory doesn't exist
**Setup:** No `~/.openclaw/` directory at all  
**Action:** Call `load_pg_env()`  
**Expected:** No error; defaults apply  

---

## 5. shell-install.sh — Config File Writing

### TC-5.1: Writes postgres.json after DB setup
**Setup:** Fresh system; `~/.openclaw/` may or may not exist  
**Action:** Run `shell-install.sh` (or relevant DB setup portion)  
**Expected:** `~/.openclaw/postgres.json` created with correct connection details matching the DB just set up  

### TC-5.2: File created with chmod 600
**Action:** After TC-5.1  
**Expected:** `stat -c '%a' ~/.openclaw/postgres.json` returns `600`  

### TC-5.3: Creates `~/.openclaw/` directory if missing
**Setup:** No `~/.openclaw/` directory  
**Action:** Run `shell-install.sh`  
**Expected:** Directory created; config file written inside it  

### TC-5.4: Does NOT overwrite existing config file
**Setup:** `~/.openclaw/postgres.json` already exists with custom values  
**Action:** Run `shell-install.sh`  
**Expected:** Existing file untouched; installer logs that it skipped writing  

### TC-5.5: Written JSON is valid and complete
**Action:** After TC-5.1, parse the written file  
**Expected:** Valid JSON with keys: `host`, `port`, `database`, `user`, `password`  

---

## 6. agent-install.sh — Config File Reading

### TC-6.1: Config file exists — reads successfully
**Setup:** Valid `~/.openclaw/postgres.json` with correct credentials  
**Action:** Run `agent-install.sh`  
**Expected:** Reads config; uses values for DB connectivity check; proceeds with install  

### TC-6.2: Config file missing — fails with clear error
**Setup:** No `~/.openclaw/postgres.json`  
**Action:** Run `agent-install.sh`  
**Expected:** Fails with error message: "Run shell-install.sh first or create ~/.openclaw/postgres.json" (or similar). Non-zero exit code.  

### TC-6.3: Config file exists but DB unreachable
**Setup:** Config file points to non-existent host  
**Action:** Run `agent-install.sh`  
**Expected:** Fails with DB connectivity error (distinct from missing config error)  

### TC-6.4: Config file with wrong credentials
**Setup:** Config file exists but password is wrong  
**Action:** Run `agent-install.sh`  
**Expected:** Fails with authentication error; clear message  

---

## 7. File Permissions & Security

### TC-7.1: Config file not world-readable
**Action:** After `shell-install.sh` creates the file  
**Expected:** No read permission for group or others (`-rw-------`)  

### TC-7.2: Password field present in config
**Action:** Inspect written config file  
**Expected:** Password stored in plaintext (acceptable for local file with 600 perms); field present  

### TC-7.3: Config file owned by current user
**Action:** After creation  
**Expected:** `stat -c '%U' ~/.openclaw/postgres.json` returns current user  

---

## 8. Cross-Language Consistency

### TC-8.1: All three loaders produce identical env vars
**Setup:** Same config file, same initial ENV state  
**Action:** Run bash, python, TypeScript loaders independently  
**Expected:** All three set identical `PG*` env var values  

### TC-8.2: All three loaders handle missing file identically
**Setup:** No config file, no ENV vars  
**Action:** Run all three loaders  
**Expected:** All three produce `PGHOST=localhost`, `PGPORT=5432`, `PGUSER=$(whoami)`; `PGDATABASE` and `PGPASSWORD` unset  

### TC-8.3: All three loaders respect ENV precedence identically
**Setup:** `PGHOST=override` set; config file has `"host": "fromfile"`  
**Action:** Run all three loaders  
**Expected:** All three: `PGHOST=override`  

---

## Summary

| Category | Count |
|---|---|
| Happy path | 4 |
| Defaults | 3 |
| Edge cases | 5 |
| Error conditions | 4 |
| shell-install.sh | 5 |
| agent-install.sh | 4 |
| Permissions & security | 3 |
| Cross-language consistency | 3 |
| **Total** | **31** |
