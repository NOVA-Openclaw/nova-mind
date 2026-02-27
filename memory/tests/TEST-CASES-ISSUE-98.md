# Test Cases: Issue #98 — Add env-loader library to ~/.openclaw/lib/

**Issue:** [#98 - Add env-loader library to ~/.openclaw/lib/ for standalone scripts](https://github.com/NOVA-Openclaw/nova-memory/issues/98)  
**Date:** 2026-02-16  
**Author:** Nova (subagent)

---

## Context

Two new library files allow standalone scripts to load environment variables from `~/.openclaw/openclaw.json` (`env.vars` section):

- `lib/env-loader.sh` — bash helper exposing `load_openclaw_env()`
- `lib/env_loader.py` — Python equivalent exposing `load_openclaw_env()`

Both follow the same resolution rules:
- Existing (non-empty) ENV vars take **precedence** and are NOT overwritten
- `null` JSON values are treated as absent (skipped)
- Empty string values are treated as unset (skipped)
- Malformed JSON prints a warning to stderr and returns gracefully

`agent-install.sh` is updated to install both files alongside existing `pg-env` libs using SHA-256 hash comparison.

### Config format (relevant section)

```json
{
  "env": {
    "vars": {
      "OPENAI_API_KEY": "sk-abc123",
      "DATABASE_URL": "postgres://localhost/mydb"
    }
  }
}
```

---

## 1. Happy Path Tests

### TEST-1.1: Bash — loads vars from valid config

| Field | Value |
|-------|-------|
| **Test Name** | `test_bash_loads_vars_from_valid_config` |
| **Description** | `load_openclaw_env()` exports all vars from a valid `openclaw.json` |
| **Setup** | Create temp `openclaw.json` with `env.vars` containing `FOO=bar`, `BAZ=qux`. Unset `FOO` and `BAZ` in env. Override `HOME` to temp dir. |
| **Input/Action** | `source env-loader.sh && load_openclaw_env && echo "$FOO $BAZ"` |
| **Expected Result** | `FOO=bar` and `BAZ=qux` are exported. Return code 0. |
| **Test Type** | Unit |

### TEST-1.2: Python — loads vars from valid config

| Field | Value |
|-------|-------|
| **Test Name** | `test_python_loads_vars_from_valid_config` |
| **Description** | `load_openclaw_env()` sets `os.environ` and returns dict for all vars |
| **Setup** | Create temp `openclaw.json` with `env.vars` containing `FOO=bar`, `BAZ=qux`. Clear those from `os.environ`. |
| **Input/Action** | `result = load_openclaw_env(config_path=tmp_config)` |
| **Expected Result** | `result == {"FOO": "bar", "BAZ": "qux"}`. `os.environ["FOO"] == "bar"`. `os.environ["BAZ"] == "qux"`. |
| **Test Type** | Unit |

### TEST-1.3: Bash — return code 0 on success

| Field | Value |
|-------|-------|
| **Test Name** | `test_bash_return_code_zero_on_success` |
| **Description** | Function returns 0 when config is valid |
| **Setup** | Valid `openclaw.json` with at least one var. |
| **Input/Action** | `load_openclaw_env; echo $?` |
| **Expected Result** | Return code is `0`. |
| **Test Type** | Unit |

---

## 2. ENV Precedence Tests

### TEST-2.1: Bash — existing env var NOT overwritten

| Field | Value |
|-------|-------|
| **Test Name** | `test_bash_existing_env_not_overwritten` |
| **Description** | Pre-existing non-empty env vars are preserved |
| **Setup** | `export FOO=original`. Config has `FOO=from_config`. |
| **Input/Action** | `load_openclaw_env && echo "$FOO"` |
| **Expected Result** | `FOO` remains `original`. |
| **Test Type** | Unit |

### TEST-2.2: Python — existing env var NOT overwritten

| Field | Value |
|-------|-------|
| **Test Name** | `test_python_existing_env_not_overwritten` |
| **Description** | Pre-existing non-empty env vars are preserved; returned dict reflects existing value |
| **Setup** | `os.environ["FOO"] = "original"`. Config has `FOO=from_config`. |
| **Input/Action** | `result = load_openclaw_env(config_path=tmp_config)` |
| **Expected Result** | `os.environ["FOO"] == "original"`. `result["FOO"] == "original"`. |
| **Test Type** | Unit |

### TEST-2.3: Bash — empty env var IS overwritten by config

| Field | Value |
|-------|-------|
| **Test Name** | `test_bash_empty_env_overwritten` |
| **Description** | An env var set to empty string is treated as unset and overwritten |
| **Setup** | `export FOO=""`. Config has `FOO=from_config`. |
| **Input/Action** | `load_openclaw_env && echo "$FOO"` |
| **Expected Result** | `FOO=from_config`. |
| **Test Type** | Unit |

---

## 3. Null JSON Values

### TEST-3.1: Bash — null value treated as absent

| Field | Value |
|-------|-------|
| **Test Name** | `test_bash_null_value_skipped` |
| **Description** | A var with JSON `null` value is not exported |
| **Setup** | Config: `{"env":{"vars":{"FOO":null,"BAR":"hello"}}}`. Unset `FOO` and `BAR`. |
| **Input/Action** | `load_openclaw_env` |
| **Expected Result** | `FOO` is not set. `BAR=hello`. Return code 0. |
| **Test Type** | Unit |

### TEST-3.2: Python — null value treated as absent

| Field | Value |
|-------|-------|
| **Test Name** | `test_python_null_value_skipped` |
| **Description** | A var with JSON `null` value is not set in os.environ or returned |
| **Setup** | Config: `{"env":{"vars":{"FOO":null,"BAR":"hello"}}}`. Clear `FOO` and `BAR`. |
| **Input/Action** | `result = load_openclaw_env(config_path=tmp_config)` |
| **Expected Result** | `"FOO" not in os.environ`. `"FOO" not in result`. `result["BAR"] == "hello"`. |
| **Test Type** | Unit |

---

## 4. Empty String Values

### TEST-4.1: Bash — empty string value treated as unset

| Field | Value |
|-------|-------|
| **Test Name** | `test_bash_empty_string_skipped` |
| **Description** | A var with `""` value in JSON is not exported |
| **Setup** | Config: `{"env":{"vars":{"FOO":"","BAR":"hello"}}}`. Unset `FOO` and `BAR`. |
| **Input/Action** | `load_openclaw_env` |
| **Expected Result** | `FOO` is not set (or empty). `BAR=hello`. |
| **Test Type** | Unit |

### TEST-4.2: Python — empty string value treated as unset

| Field | Value |
|-------|-------|
| **Test Name** | `test_python_empty_string_skipped` |
| **Description** | A var with `""` value in JSON is not set |
| **Setup** | Config: `{"env":{"vars":{"FOO":"","BAR":"hello"}}}`. Clear `FOO` and `BAR`. |
| **Input/Action** | `result = load_openclaw_env(config_path=tmp_config)` |
| **Expected Result** | `"FOO" not in os.environ`. `"FOO" not in result`. `result["BAR"] == "hello"`. |
| **Test Type** | Unit |

---

## 5. Malformed JSON

### TEST-5.1: Bash — malformed JSON warns to stderr and returns 1

| Field | Value |
|-------|-------|
| **Test Name** | `test_bash_malformed_json_warns` |
| **Description** | Invalid JSON triggers a warning on stderr and returns non-zero |
| **Setup** | Config file contains `{not valid json`. |
| **Input/Action** | `load_openclaw_env 2>stderr.txt; echo $?; cat stderr.txt` |
| **Expected Result** | Return code is `1`. stderr contains `WARNING: Malformed JSON`. No vars exported. |
| **Test Type** | Unit |

### TEST-5.2: Python — malformed JSON warns to stderr and returns empty

| Field | Value |
|-------|-------|
| **Test Name** | `test_python_malformed_json_warns` |
| **Description** | Invalid JSON triggers a warning on stderr and returns empty dict |
| **Setup** | Config file contains `{not valid json`. Capture stderr. |
| **Input/Action** | `result = load_openclaw_env(config_path=tmp_config)` |
| **Expected Result** | `result == {}`. stderr contains `WARNING`. No env vars set. No exception raised. |
| **Test Type** | Unit |

### TEST-5.3: Python — non-dict top-level JSON warns

| Field | Value |
|-------|-------|
| **Test Name** | `test_python_non_dict_json_warns` |
| **Description** | A JSON array or scalar at top level is not a valid config |
| **Setup** | Config file contains `[1, 2, 3]`. |
| **Input/Action** | `result = load_openclaw_env(config_path=tmp_config)` |
| **Expected Result** | `result == {}`. stderr contains `WARNING`. |
| **Test Type** | Unit |

---

## 6. Missing Config File

### TEST-6.1: Bash — missing config file returns 0 silently

| Field | Value |
|-------|-------|
| **Test Name** | `test_bash_missing_config_no_error` |
| **Description** | If `openclaw.json` doesn't exist, function returns cleanly |
| **Setup** | `HOME` points to a temp dir with no `.openclaw/openclaw.json`. |
| **Input/Action** | `load_openclaw_env 2>stderr.txt; echo $?; cat stderr.txt` |
| **Expected Result** | Return code `0`. stderr is empty. No vars exported. |
| **Test Type** | Unit |

### TEST-6.2: Python — missing config file returns empty dict silently

| Field | Value |
|-------|-------|
| **Test Name** | `test_python_missing_config_no_error` |
| **Description** | If config file doesn't exist, returns `{}` with no output |
| **Setup** | `config_path` points to non-existent file. |
| **Input/Action** | `result = load_openclaw_env(config_path="/tmp/nonexistent.json")` |
| **Expected Result** | `result == {}`. No stderr output. No exception. |
| **Test Type** | Unit |

---

## 7. Unreadable Config File (Permissions)

### TEST-7.1: Bash — unreadable config returns 0 silently

| Field | Value |
|-------|-------|
| **Test Name** | `test_bash_unreadable_config_silent` |
| **Description** | Config exists but is not readable (chmod 000) — treated like missing |
| **Setup** | Create config file, `chmod 000` on it. |
| **Input/Action** | `load_openclaw_env 2>stderr.txt; echo $?` |
| **Expected Result** | Return code `0`. No vars exported. No error on stderr. |
| **Test Type** | Unit |

### TEST-7.2: Python — unreadable config warns and returns empty

| Field | Value |
|-------|-------|
| **Test Name** | `test_python_unreadable_config_warns` |
| **Description** | Config exists but is not readable — warns on stderr |
| **Setup** | Create config file, `chmod 000` on it. |
| **Input/Action** | `result = load_openclaw_env(config_path=tmp_config)` |
| **Expected Result** | `result == {}`. stderr contains `WARNING: Failed to read`. No exception raised. |
| **Test Type** | Unit |

---

## 8. Missing env / env.vars Section

### TEST-8.1: Bash — config with no env section

| Field | Value |
|-------|-------|
| **Test Name** | `test_bash_no_env_section` |
| **Description** | Valid JSON but no `env` key at all |
| **Setup** | Config: `{"gateway":{"port":3000}}`. |
| **Input/Action** | `load_openclaw_env; echo $?` |
| **Expected Result** | Return code `0`. No vars exported. No errors. |
| **Test Type** | Unit |

### TEST-8.2: Bash — config with env but no vars

| Field | Value |
|-------|-------|
| **Test Name** | `test_bash_env_without_vars` |
| **Description** | `env` section exists but has no `vars` key |
| **Setup** | Config: `{"env":{"model":"gpt-4"}}`. |
| **Input/Action** | `load_openclaw_env; echo $?` |
| **Expected Result** | Return code `0`. No vars exported. No errors. |
| **Test Type** | Unit |

### TEST-8.3: Python — config with no env section

| Field | Value |
|-------|-------|
| **Test Name** | `test_python_no_env_section` |
| **Description** | Valid JSON but no `env` key |
| **Setup** | Config: `{"gateway":{"port":3000}}`. |
| **Input/Action** | `result = load_openclaw_env(config_path=tmp_config)` |
| **Expected Result** | `result == {}`. No env vars set. |
| **Test Type** | Unit |

### TEST-8.4: Python — env.vars is not a dict

| Field | Value |
|-------|-------|
| **Test Name** | `test_python_env_vars_not_dict` |
| **Description** | `env.vars` exists but is a string or array instead of object |
| **Setup** | Config: `{"env":{"vars":"not_a_dict"}}`. |
| **Input/Action** | `result = load_openclaw_env(config_path=tmp_config)` |
| **Expected Result** | `result == {}`. No env vars set. No exception. |
| **Test Type** | Unit |

---

## 9. agent-install.sh — Installation Tests

### TEST-9.1: Fresh install copies both new lib files

| Field | Value |
|-------|-------|
| **Test Name** | `test_install_copies_new_lib_files` |
| **Description** | Running `agent-install.sh` installs `env-loader.sh` and `env_loader.py` to `~/.openclaw/lib/` |
| **Setup** | `~/.openclaw/lib/` exists but does not contain `env-loader.sh` or `env_loader.py`. |
| **Input/Action** | Run `agent-install.sh` (or invoke `install_lib_files` function). |
| **Expected Result** | `~/.openclaw/lib/env-loader.sh` exists and matches `lib/env-loader.sh` (byte-for-byte). `~/.openclaw/lib/env_loader.py` exists and matches `lib/env_loader.py`. |
| **Test Type** | Integration |

### TEST-9.2: SHA-256 hash comparison detects changes

| Field | Value |
|-------|-------|
| **Test Name** | `test_install_updates_changed_file` |
| **Description** | If installed file differs from source, it is replaced |
| **Setup** | Install files first. Then modify `~/.openclaw/lib/env-loader.sh` (append a comment). |
| **Input/Action** | Run `agent-install.sh` again. |
| **Expected Result** | `~/.openclaw/lib/env-loader.sh` is overwritten with the source version. SHA-256 of installed file matches source. |
| **Test Type** | Integration |

### TEST-9.3: Idempotent re-run — files already up to date

| Field | Value |
|-------|-------|
| **Test Name** | `test_install_idempotent_noop` |
| **Description** | Running install twice produces no changes on second run |
| **Setup** | Run `agent-install.sh` once successfully. |
| **Input/Action** | Run `agent-install.sh` again. Capture output. |
| **Expected Result** | Output indicates files are "up to date" (or no copy messages). Files unchanged. Exit code 0. |
| **Test Type** | Integration |

### TEST-9.4: All five lib files installed together

| Field | Value |
|-------|-------|
| **Test Name** | `test_install_all_five_lib_files` |
| **Description** | The updated files array includes all 5 libs |
| **Setup** | Clean `~/.openclaw/lib/` directory. |
| **Input/Action** | Run `agent-install.sh`. |
| **Expected Result** | All of `pg-env.sh`, `pg_env.py`, `pg-env.ts`, `env-loader.sh`, `env_loader.py` exist in `~/.openclaw/lib/`. |
| **Test Type** | Integration |

---

## 10. Edge Cases

### TEST-10.1: Bash — var with special characters in value

Values are assigned via `export "$key=$val"` where `$val` comes from `jq -r` captured in `$()`. Double-quoting the export protects against most shell interpretation, but each character class should be verified explicitly.

| Field | Value |
|-------|-------|
| **Test Name** | `test_bash_special_chars_in_value` |
| **Description** | Values containing dangerous shell characters are exported correctly |
| **Setup** | Config with `env.vars` containing all sub-cases below. Unset all test vars. |
| **Test Type** | Unit |

**Sub-cases (all must pass):**

| Sub-case | Key | JSON Value | Expected `$KEY` | Why it matters |
|----------|-----|-----------|-----------------|----------------|
| 10.1a Spaces | `SC_SPACE` | `"hello world"` | `hello world` | Unquoted would word-split |
| 10.1b Single quotes | `SC_SQUOTE` | `"it's fine"` | `it's fine` | Could break single-quoted contexts |
| 10.1c Double quotes | `SC_DQUOTE` | `"say \"hi\""` | `say "hi"` | Could break `export` if unquoted |
| 10.1d Backticks | `SC_BTICK` | `` "run `cmd`" `` | `` run `cmd` `` | Unquoted would attempt command substitution |
| 10.1e Dollar signs | `SC_DOLLAR` | `"costs $100"` | `costs $100` | Unquoted would attempt variable expansion |
| 10.1f Backslashes | `SC_BSLASH` | `"path\\to\\file"` | `path\to\file` | Could be interpreted as escape sequences |
| 10.1g Ampersand/semicolon | `SC_SHELL` | `"a && b; c"` | `a && b; c` | Shell metacharacters |
| 10.1h Newlines | `SC_NEWLINE` | `"line1\nline2"` | `line1\nline2` | **Note:** `jq -r` outputs literal newlines; `$()` strips trailing newlines. Values with embedded newlines will have them preserved (except trailing). This is a known limitation of shell command substitution. |

**Mechanism analysis:** The code uses `val=$(echo "$json" | jq -r --arg k "$key" '.env.vars[$k] // empty')` then `export "$key=$val"`. Because `$val` is already a shell variable at export time, double-quoting prevents re-interpretation of backticks, `$`, etc. The main risk is the `eval "current=\${$key:-}"` line — if a *key name* contained special chars it could be exploited, but JSON object keys from `jq` are safe identifier strings in practice.

### TEST-10.2: Bash — env.vars is not a dict (string)

| Field | Value |
|-------|-------|
| **Test Name** | `test_bash_env_vars_not_dict_string` |
| **Description** | `env.vars` is a string instead of an object — bash should handle gracefully |
| **Setup** | Config: `{"env":{"vars":"not_a_dict"}}`. |
| **Input/Action** | `load_openclaw_env 2>stderr.txt; echo $?` |
| **Expected Result** | Return code `0`. No vars exported. No crash. |
| **Notes** | `jq -r '.env.vars // {} \| keys[]'` **errors** on strings ("has no keys"), returning non-zero. The `\|\| return 0` in the code catches this — function returns 0 cleanly. |
| **Test Type** | Unit |

### TEST-10.3: Bash — env.vars is not a dict (array)

| Field | Value |
|-------|-------|
| **Test Name** | `test_bash_env_vars_not_dict_array` |
| **Description** | `env.vars` is an array instead of an object — bash should handle gracefully |
| **Setup** | Config: `{"env":{"vars":[1,2,3]}}`. Unset vars named `0`, `1`, `2`. |
| **Input/Action** | `load_openclaw_env 2>stderr.txt; echo $?` |
| **Expected Result** | Return code `0`. No meaningful vars exported. |
| **Notes** | ⚠️ **Known issue:** `jq -r '.env.vars // {} \| keys[]'` on an array returns numeric indices (`0`, `1`, `2`). The code will attempt `jq -r --arg k "0" '.env.vars[$k]'` which returns `null`/empty for string keys on arrays, so no vars are actually exported. However this is fragile — a type-check (`jq -r '.env.vars \| if type == "object" then ... '`) would be more robust. |
| **Test Type** | Unit |

### TEST-10.4: Bash — multiple sequential calls (idempotency)

| Field | Value |
|-------|-------|
| **Test Name** | `test_bash_idempotent_double_call` |
| **Description** | Calling `load_openclaw_env` twice in the same shell is safe and idempotent |
| **Setup** | Config: `{"env":{"vars":{"FOO":"bar"}}}`. Unset `FOO`. |
| **Input/Action** | `load_openclaw_env && load_openclaw_env && echo "$FOO"` |
| **Expected Result** | `FOO=bar`. Return code `0` for both calls. Second call sees `FOO` is already set (non-empty) and skips it — no double-setting. |
| **Test Type** | Unit |

### TEST-10.5: Python — multiple sequential calls (idempotency)

| Field | Value |
|-------|-------|
| **Test Name** | `test_python_idempotent_double_call` |
| **Description** | Calling `load_openclaw_env()` twice in the same process is safe and idempotent |
| **Setup** | Config: `{"env":{"vars":{"FOO":"bar","BAZ":"qux"}}}`. Clear `FOO` and `BAZ`. |
| **Input/Action** | `r1 = load_openclaw_env(config_path=tmp); r2 = load_openclaw_env(config_path=tmp)` |
| **Expected Result** | `r1 == r2 == {"FOO": "bar", "BAZ": "qux"}`. `os.environ["FOO"] == "bar"`. Second call doesn't error or duplicate values. |
| **Test Type** | Unit |

### TEST-10.6: Python — numeric JSON value converted to string

| Field | Value |
|-------|-------|
| **Test Name** | `test_python_numeric_value_as_string` |
| **Description** | Non-string JSON values (int, bool) are converted via `str()` |
| **Setup** | Config: `{"env":{"vars":{"PORT":8080,"DEBUG":true}}}`. |
| **Input/Action** | `result = load_openclaw_env(config_path=tmp_config)` |
| **Expected Result** | `os.environ["PORT"] == "8080"`. `os.environ["DEBUG"] == "True"`. |
| **Test Type** | Unit |

### TEST-10.7: Python — custom config_path parameter

| Field | Value |
|-------|-------|
| **Test Name** | `test_python_custom_config_path` |
| **Description** | Passing explicit `config_path` overrides default `~/.openclaw/openclaw.json` |
| **Setup** | Create config at `/tmp/custom-config.json` with `FOO=custom`. |
| **Input/Action** | `result = load_openclaw_env(config_path="/tmp/custom-config.json")` |
| **Expected Result** | `result["FOO"] == "custom"`. Default path not consulted. |
| **Test Type** | Unit |
