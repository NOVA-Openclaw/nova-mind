#!/usr/bin/env node
// test-handler.js — Chunk 2 tests for issue #497
// Validates config-driven timeout, exit-code taxonomy, and non-blocking invariants.

const fs = require('fs');
const path = require('path');
const { execSync } = require('child_process');
const { promisify } = require('util');
const cp = require('child_process');

const execFileAsync = promisify(cp.execFile);

function requireEnv(name) {
  const val = process.env[name];
  if (!val) {
    console.error(`ERROR: ${name} is not set`);
    process.exit(1);
  }
  return val;
}

const TEST_PGDATABASE = requireEnv('TEST_PGDATABASE');
const TEST_PGUSER = requireEnv('TEST_PGUSER');
const TEST_PGHOST = requireEnv('TEST_PGHOST');
const TEST_PGUSER_DDL = process.env.TEST_PGUSER_DDL || TEST_PGUSER;

const REPO_ROOT = path.resolve(__dirname, '../..');
const HANDLER_TS = path.join(REPO_ROOT, 'memory/hooks/memory-extract/handler.ts');
const COMPILE_DIR = fs.mkdtempSync('/tmp/issue497-handler-');
const HANDLER_JS = path.join(COMPILE_DIR, 'handler.js');
const MOCKS_DIR = fs.mkdtempSync('/tmp/issue497-mocks-');
const CONFIG_DIR = fs.mkdtempSync('/tmp/issue497-config-');
const CONFIG_PATH = path.join(CONFIG_DIR, 'memory-extraction-config.json');
const LOG_FILE = process.argv[2] || '/tmp/issue497-handler-test.log';

process.env.PGDATABASE = TEST_PGDATABASE;
process.env.PGUSER = TEST_PGUSER;
process.env.PGHOST = TEST_PGHOST;
delete process.env.PGPASSWORD;

const PASS = [];
const FAIL = [];
let currentCase = null;

function log(...args) {
  const line = `[issue-497:chunk2] ${args.join(' ')}`;
  fs.appendFileSync(LOG_FILE, line + '\n');
  console.log(line);
}

function assert(name, expected, actual) {
  const ok = expected === actual;
  if (ok) {
    PASS.push(name);
    log(`PASS: ${name}`);
  } else {
    FAIL.push(name);
    log(`FAIL: ${name} (expected=${JSON.stringify(expected)}, actual=${JSON.stringify(actual)})`);
  }
  return ok;
}

function assertTrue(name, actual) {
  return assert(name, true, actual);
}

function assertContains(name, haystack, needle) {
  const ok = haystack.includes(needle);
  if (ok) {
    PASS.push(name);
    log(`PASS: ${name}`);
  } else {
    FAIL.push(name);
    log(`FAIL: ${name} (expected to contain ${JSON.stringify(needle)})`);
  }
  return ok;
}

async function psql(sql, user) {
  delete process.env.PGPASSWORD;
  const u = user || TEST_PGUSER;
  const { stdout } = await execFileAsync('psql', ['-U', u, '-d', TEST_PGDATABASE, '-h', TEST_PGHOST, '-t', '-A', '-c', sql]);
  return stdout.trim();
}

async function psqlAsDdl(sql) {
  return psql(sql, TEST_PGUSER_DDL);
}

async function cleanupSession(sessionKey) {
  try {
    await psqlAsDdl(`DELETE FROM extraction_failures WHERE session_key = '${sessionKey.replace(/'/g, "''")}';`);
    await psqlAsDdl(`DELETE FROM channel_transcripts WHERE external_message_id LIKE '${sessionKey.replace(/'/g, "''")}%';`);
    await psqlAsDdl(`DELETE FROM channel_sessions WHERE session_key = '${sessionKey.replace(/'/g, "''")}';`);
  } catch (e) {
    // ignore cleanup errors
  }
}

function compileHandler() {
  const cmd = `tsc "${HANDLER_TS}" --outDir "${COMPILE_DIR}" --module commonjs --noEmitOnError false --noImplicitAny false`;
  log('Compiling handler.ts...');
  try {
    execSync(cmd, { stdio: 'pipe', cwd: REPO_ROOT });
  } catch (err) {
    log('tsc emitted errors (expected without @types/node), continuing if JS exists');
  }
  if (!fs.existsSync(HANDLER_JS)) {
    throw new Error('handler.js not produced');
  }
  log(`Compiled handler to ${HANDLER_JS}`);
}

function writeMock(name, code) {
  const p = path.join(MOCKS_DIR, `${name}.py`);
  fs.writeFileSync(p, code, { mode: 0o755 });
  return p;
}

function writeConfig(obj) {
  fs.writeFileSync(CONFIG_PATH, JSON.stringify(obj), { mode: 0o644 });
}

function deleteConfig() {
  try { fs.unlinkSync(CONFIG_PATH); } catch (e) {}
}

function captureLogs() {
  const logs = [];
  const orig = {
    info: console.info,
    error: console.error,
    warn: console.warn,
    debug: console.debug,
    log: console.log
  };
  console.info = (...a) => logs.push(['INFO', a.map(x => typeof x === 'object' ? JSON.stringify(x) : String(x)).join(' ')]);
  console.error = (...a) => logs.push(['ERROR', a.map(x => typeof x === 'object' ? JSON.stringify(x) : String(x)).join(' ')]);
  console.warn = (...a) => logs.push(['WARN', a.map(x => typeof x === 'object' ? JSON.stringify(x) : String(x)).join(' ')]);
  console.debug = (...a) => logs.push(['DEBUG', a.map(x => typeof x === 'object' ? JSON.stringify(x) : String(x)).join(' ')]);
  console.log = (...a) => logs.push(['LOG', a.map(x => typeof x === 'object' ? JSON.stringify(x) : String(x)).join(' ')]);
  return {
    logs,
    restore: () => Object.assign(console, orig),
    text: () => logs.map(l => l.join(': ')).join('\n')
  };
}

async function callHandler(handler, event) {
  await handler(event);
  // Wait for child events / dead-letter inserts to finish.
  await new Promise(r => setTimeout(r, 800));
}

async function waitForDeadLetter(sessionKey, timeoutMs = 5000) {
  const start = Date.now();
  while (Date.now() - start < timeoutMs) {
    const cnt = await psql(`SELECT COUNT(*) FROM extraction_failures WHERE session_key = '${sessionKey.replace(/'/g, "''")}';`);
    if (cnt === '1') return true;
    await new Promise(r => setTimeout(r, 200));
  }
  return false;
}

async function runCase(name, fn) {
  currentCase = name;
  log(`\n=== ${name} ===`);
  try {
    await fn();
  } catch (err) {
    log(`ERROR in ${name}: ${err.message}\n${err.stack}`);
    FAIL.push(`${name} (exception)`);
  }
}

// ---------------------------------------------------------------------------
// Mock scripts
// ---------------------------------------------------------------------------

const mocks = {
  sleep3: writeMock('sleep3', `
import sys, time
sys.stdin.read()
time.sleep(3)
`),
  sleep5: writeMock('sleep5', `
import sys, time
sys.stdin.read()
time.sleep(5)
`),
  exit0: writeMock('exit0', `
import sys
sys.stdin.read()
sys.exit(0)
`),
  exit1: writeMock('exit1', `
import sys
sys.stdin.read()
sys.stderr.write('generic failure\\n')
sys.exit(1)
`),
  exit2: writeMock('exit2', `
import sys
sys.stdin.read()
sys.stderr.write('json parse failure\\n')
sys.exit(2)
`),
  exit3: writeMock('exit3', `
import sys
sys.stdin.read()
sys.stderr.write('other nonzero\\n')
sys.exit(3)
`),
  exit255: writeMock('exit255', `
import sys
sys.stdin.read()
sys.stderr.write('exit 255\\n')
sys.exit(255)
`)
};

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

async function main() {
  log(`Started at ${new Date().toISOString()}`);
  log(`Log file: ${LOG_FILE}`);
  compileHandler();

  // Base environment: point config path to temp file, clear override.
  process.env.EXTRACTION_CONFIG_PATH_OVERRIDE = CONFIG_PATH;
  delete process.env.EXTRACTION_TIMEOUT_MS_OVERRIDE;
  let handler = require(HANDLER_JS).default;

  // TC-A1: config key present, valid value honored.
  await runCase('TC-A1 config timeout honored', async () => {
    const sessionKey = 'tc-a1-' + Date.now();
    writeConfig({ extraction_timeout_ms: 1500 });
    process.env.EXTRACTION_SCRIPT_PATH_OVERRIDE = mocks.sleep5;
    delete process.env.EXTRACTION_TIMEOUT_MS_OVERRIDE;
    await cleanupSession(sessionKey);
    const start = Date.now();
    await callHandler(handler, {
      type: 'message', action: 'received', sessionKey,
      context: { rawBody: 'This is a config timeout test message with enough length.', metadata: { senderName: 'TC-A1', senderId: 'tc-a1-user' } }
    });
    const ok = await waitForDeadLetter(sessionKey, 5000);
    const elapsed = Date.now() - start;
    assertTrue('TC-A1: dead-letter row written', ok);
    assertTrue('TC-A1: child killed near 1500ms', elapsed >= 1300 && elapsed <= 3000);
    const row = await psql(`SELECT failure_reason FROM extraction_failures WHERE session_key = '${sessionKey}';`);
    assert('TC-A1: failure_reason = timeout', 'timeout', row);
    await cleanupSession(sessionKey);
  });

  // TC-A2: config key absent -> default is used (proves fallback path).
  await runCase('TC-A2 config key absent falls back', async () => {
    const sessionKey = 'tc-a2-' + Date.now();
    writeConfig({ provider: 'openrouter' });
    process.env.EXTRACTION_SCRIPT_PATH_OVERRIDE = mocks.sleep3;
    delete process.env.EXTRACTION_TIMEOUT_MS_OVERRIDE;
    await cleanupSession(sessionKey);
    const start = Date.now();
    await callHandler(handler, {
      type: 'message', action: 'received', sessionKey,
      context: { rawBody: 'This is a fallback timeout test message with enough length.', metadata: { senderName: 'TC-A2', senderId: 'tc-a2-user' } }
    });
    // Child sleeps 3s; default is 90s, so it should complete on its own.
    await new Promise(r => setTimeout(r, 3800));
    const elapsed = Date.now() - start;
    const cnt = await psql(`SELECT COUNT(*) FROM extraction_failures WHERE session_key = '${sessionKey}';`);
    assert('TC-A2: no dead-letter row (default > 3s)', '0', cnt);
    assertTrue('TC-A2: child completed in under 90s default', elapsed < 10000);
    await cleanupSession(sessionKey);
  });

  // TC-A3: missing config file -> fallback default, no crash.
  await runCase('TC-A3 missing config file', async () => {
    const sessionKey = 'tc-a3-' + Date.now();
    deleteConfig();
    process.env.EXTRACTION_SCRIPT_PATH_OVERRIDE = mocks.sleep3;
    delete process.env.EXTRACTION_TIMEOUT_MS_OVERRIDE;
    await cleanupSession(sessionKey);
    const cap = captureLogs();
    const start = Date.now();
    await callHandler(handler, {
      type: 'message', action: 'received', sessionKey,
      context: { rawBody: 'Missing config file test message with enough length.', metadata: { senderName: 'TC-A3', senderId: 'tc-a3-user' } }
    });
    await new Promise(r => setTimeout(r, 3800));
    const elapsed = Date.now() - start;
    cap.restore();
    const cnt = await psql(`SELECT COUNT(*) FROM extraction_failures WHERE session_key = '${sessionKey}';`);
    assert('TC-A3: no dead-letter row', '0', cnt);
    assertTrue('TC-A3: handler did not crash', elapsed < 10000);
    await cleanupSession(sessionKey);
  });

  // TC-A4: malformed config JSON -> fallback default.
  await runCase('TC-A4 malformed config JSON', async () => {
    const sessionKey = 'tc-a4-' + Date.now();
    fs.writeFileSync(CONFIG_PATH, '{not valid json');
    process.env.EXTRACTION_SCRIPT_PATH_OVERRIDE = mocks.sleep3;
    delete process.env.EXTRACTION_TIMEOUT_MS_OVERRIDE;
    await cleanupSession(sessionKey);
    const start = Date.now();
    await callHandler(handler, {
      type: 'message', action: 'received', sessionKey,
      context: { rawBody: 'Malformed config test message with enough length.', metadata: { senderName: 'TC-A4', senderId: 'tc-a4-user' } }
    });
    await new Promise(r => setTimeout(r, 3800));
    const elapsed = Date.now() - start;
    const cnt = await psql(`SELECT COUNT(*) FROM extraction_failures WHERE session_key = '${sessionKey}';`);
    assert('TC-A4: no dead-letter row', '0', cnt);
    assertTrue('TC-A4: handler did not crash', elapsed < 10000);
    await cleanupSession(sessionKey);
  });

  // TC-A5: non-numeric / zero / negative config values fall back.
  await runCase('TC-A5 invalid config values fall back', async () => {
    for (const badValue of ['sixty seconds', 0, -5000]) {
      const sessionKey = 'tc-a5-' + badValue + '-' + Date.now();
      writeConfig({ extraction_timeout_ms: badValue });
      process.env.EXTRACTION_SCRIPT_PATH_OVERRIDE = mocks.sleep3;
      delete process.env.EXTRACTION_TIMEOUT_MS_OVERRIDE;
      await cleanupSession(sessionKey);
      const start = Date.now();
      await callHandler(handler, {
        type: 'message', action: 'received', sessionKey,
        context: { rawBody: 'Invalid config value test message with enough length.', metadata: { senderName: 'TC-A5', senderId: 'tc-a5-user' } }
      });
      await new Promise(r => setTimeout(r, 3800));
      const elapsed = Date.now() - start;
      const cnt = await psql(`SELECT COUNT(*) FROM extraction_failures WHERE session_key = '${sessionKey}';`);
      assert(`TC-A5 (${JSON.stringify(badValue)}): no dead-letter row`, '0', cnt);
      assertTrue(`TC-A5 (${JSON.stringify(badValue)}): handler did not crash`, elapsed < 10000);
      await cleanupSession(sessionKey);
    }
  });

  // TC-A6: hot reload - config change between events is honored.
  await runCase('TC-A6 hot reload config change', async () => {
    const sessionKey1 = 'tc-a6-first-' + Date.now();
    const sessionKey2 = 'tc-a6-second-' + Date.now();
    writeConfig({ extraction_timeout_ms: 5000 });
    process.env.EXTRACTION_SCRIPT_PATH_OVERRIDE = mocks.sleep3;
    delete process.env.EXTRACTION_TIMEOUT_MS_OVERRIDE;
    await cleanupSession(sessionKey1);
    await cleanupSession(sessionKey2);

    // First event: 5s timeout, child sleeps 3s -> should complete.
    await callHandler(handler, {
      type: 'message', action: 'received', sessionKey: sessionKey1,
      context: { rawBody: 'Hot reload first event test message with enough length.', metadata: { senderName: 'TC-A6a', senderId: 'tc-a6a-user' } }
    });
    await new Promise(r => setTimeout(r, 3800));
    const cnt1 = await psql(`SELECT COUNT(*) FROM extraction_failures WHERE session_key = '${sessionKey1}';`);
    assert('TC-A6: first event completed with 5s timeout', '0', cnt1);

    // Rewrite config to 1s timeout WITHOUT restarting gateway.
    writeConfig({ extraction_timeout_ms: 1000 });
    process.env.EXTRACTION_SCRIPT_PATH_OVERRIDE = mocks.sleep3;
    const start2 = Date.now();
    await callHandler(handler, {
      type: 'message', action: 'received', sessionKey: sessionKey2,
      context: { rawBody: 'Hot reload second event test message with enough length.', metadata: { senderName: 'TC-A6b', senderId: 'tc-a6b-user' } }
    });
    const ok2 = await waitForDeadLetter(sessionKey2, 5000);
    const elapsed2 = Date.now() - start2;
    assertTrue('TC-A6: second event dead-letter written', ok2);
    assertTrue('TC-A6: second event killed near 1000ms', elapsed2 >= 800 && elapsed2 <= 3000);
    const reason2 = await psql(`SELECT failure_reason FROM extraction_failures WHERE session_key = '${sessionKey2}';`);
    assert('TC-A6: second event reason = timeout', 'timeout', reason2);
    await cleanupSession(sessionKey1);
    await cleanupSession(sessionKey2);
  });

  // TC-A7: env override wins over config.
  await runCase('TC-A7 env override precedence', async () => {
    const sessionKey = 'tc-a7-' + Date.now();
    writeConfig({ extraction_timeout_ms: 5000 });
    process.env.EXTRACTION_SCRIPT_PATH_OVERRIDE = mocks.sleep3;
    process.env.EXTRACTION_TIMEOUT_MS_OVERRIDE = '1000';
    await cleanupSession(sessionKey);
    const start = Date.now();
    await callHandler(handler, {
      type: 'message', action: 'received', sessionKey,
      context: { rawBody: 'Env override precedence test message with enough length.', metadata: { senderName: 'TC-A7', senderId: 'tc-a7-user' } }
    });
    const ok = await waitForDeadLetter(sessionKey, 5000);
    const elapsed = Date.now() - start;
    assertTrue('TC-A7: dead-letter row written', ok);
    assertTrue('TC-A7: child killed near env override 1000ms', elapsed >= 800 && elapsed <= 3000);
    const reason = await psql(`SELECT failure_reason FROM extraction_failures WHERE session_key = '${sessionKey}';`);
    assert('TC-A7: failure_reason = timeout', 'timeout', reason);
    delete process.env.EXTRACTION_TIMEOUT_MS_OVERRIDE;
    await cleanupSession(sessionKey);
  });

  // TC-D4: exit code 2 -> json_parse_failure.
  await runCase('TC-D4 exit code 2 maps to json_parse_failure', async () => {
    const sessionKey = 'tc-d4-' + Date.now();
    writeConfig({ extraction_timeout_ms: 90000 });
    process.env.EXTRACTION_SCRIPT_PATH_OVERRIDE = mocks.exit2;
    delete process.env.EXTRACTION_TIMEOUT_MS_OVERRIDE;
    await cleanupSession(sessionKey);
    await callHandler(handler, {
      type: 'message', action: 'received', sessionKey,
      context: { rawBody: 'Exit code 2 test message with enough length.', metadata: { senderName: 'TC-D4', senderId: 'tc-d4-user' } }
    });
    const ok = await waitForDeadLetter(sessionKey);
    assertTrue('TC-D4: dead-letter row written', ok);
    const row = await psql(`SELECT exit_code, failure_reason, stderr_tail FROM extraction_failures WHERE session_key = '${sessionKey}';`);
    const [exitCode, reason, stderr] = row.split('|');
    assert('TC-D4: exit_code = 2', '2', exitCode);
    assert('TC-D4: failure_reason = json_parse_failure', 'json_parse_failure', reason);
    assertContains('TC-D4: stderr tail captured', stderr, 'json parse failure');
    await cleanupSession(sessionKey);
  });

  // TC-D5: exit code 1 -> nonzero_exit.
  await runCase('TC-D5 exit code 1 maps to nonzero_exit', async () => {
    const sessionKey = 'tc-d5-' + Date.now();
    writeConfig({ extraction_timeout_ms: 90000 });
    process.env.EXTRACTION_SCRIPT_PATH_OVERRIDE = mocks.exit1;
    delete process.env.EXTRACTION_TIMEOUT_MS_OVERRIDE;
    await cleanupSession(sessionKey);
    await callHandler(handler, {
      type: 'message', action: 'received', sessionKey,
      context: { rawBody: 'Exit code 1 test message with enough length.', metadata: { senderName: 'TC-D5', senderId: 'tc-d5-user' } }
    });
    const ok = await waitForDeadLetter(sessionKey);
    assertTrue('TC-D5: dead-letter row written', ok);
    const row = await psql(`SELECT exit_code, failure_reason FROM extraction_failures WHERE session_key = '${sessionKey}';`);
    const [exitCode, reason] = row.split('|');
    assert('TC-D5: exit_code = 1', '1', exitCode);
    assert('TC-D5: failure_reason = nonzero_exit', 'nonzero_exit', reason);
    await cleanupSession(sessionKey);
  });

  // TC-D6: timeout takes precedence over exit-code inspection.
  await runCase('TC-D6 timeout precedence over exit code', async () => {
    const sessionKey = 'tc-d6-' + Date.now();
    writeConfig({ extraction_timeout_ms: 90000 });
    process.env.EXTRACTION_SCRIPT_PATH_OVERRIDE = mocks.sleep5;
    process.env.EXTRACTION_TIMEOUT_MS_OVERRIDE = '1000';
    await cleanupSession(sessionKey);
    await callHandler(handler, {
      type: 'message', action: 'received', sessionKey,
      context: { rawBody: 'Timeout precedence test message with enough length.', metadata: { senderName: 'TC-D6', senderId: 'tc-d6-user' } }
    });
    const ok = await waitForDeadLetter(sessionKey, 5000);
    assertTrue('TC-D6: dead-letter row written', ok);
    const reason = await psql(`SELECT failure_reason FROM extraction_failures WHERE session_key = '${sessionKey}';`);
    assert('TC-D6: failure_reason = timeout', 'timeout', reason);
    delete process.env.EXTRACTION_TIMEOUT_MS_OVERRIDE;
    await cleanupSession(sessionKey);
  });

  // TC-D8: exit code boundary values.
  await runCase('TC-D8 exit code boundaries', async () => {
    const cases = [
      { mock: mocks.exit0, expectedReason: null, expectDeadLetter: false, label: 'exit 0' },
      { mock: mocks.exit1, expectedReason: 'nonzero_exit', expectDeadLetter: true, label: 'exit 1' },
      { mock: mocks.exit2, expectedReason: 'json_parse_failure', expectDeadLetter: true, label: 'exit 2' },
      { mock: mocks.exit3, expectedReason: 'nonzero_exit', expectDeadLetter: true, label: 'exit 3' },
      { mock: mocks.exit255, expectedReason: 'nonzero_exit', expectDeadLetter: true, label: 'exit 255' },
    ];
    for (const c of cases) {
      const sessionKey = 'tc-d8-' + c.label.replace(/ /g, '-') + '-' + Date.now();
      writeConfig({ extraction_timeout_ms: 90000 });
      process.env.EXTRACTION_SCRIPT_PATH_OVERRIDE = c.mock;
      delete process.env.EXTRACTION_TIMEOUT_MS_OVERRIDE;
      await cleanupSession(sessionKey);
      await callHandler(handler, {
        type: 'message', action: 'received', sessionKey,
        context: { rawBody: 'Boundary test message with enough length.', metadata: { senderName: 'TC-D8', senderId: 'tc-d8-user' } }
      });
      const cnt = await psql(`SELECT COUNT(*) FROM extraction_failures WHERE session_key = '${sessionKey}';`);
      assert(`TC-D8 (${c.label}): dead-letter presence`, c.expectDeadLetter ? '1' : '0', cnt);
      if (c.expectDeadLetter) {
        const reason = await psql(`SELECT failure_reason FROM extraction_failures WHERE session_key = '${sessionKey}';`);
        assert(`TC-D8 (${c.label}): failure_reason`, c.expectedReason, reason);
      }
      await cleanupSession(sessionKey);
    }
  });

  // TC-G1: handler returns before child completes.
  await runCase('TC-G1 handler non-blocking', async () => {
    writeConfig({ extraction_timeout_ms: 90000 });
    process.env.EXTRACTION_SCRIPT_PATH_OVERRIDE = mocks.sleep3;
    delete process.env.EXTRACTION_TIMEOUT_MS_OVERRIDE;
    const start = Date.now();
    await handler({
      type: 'message', action: 'received', sessionKey: 'tc-g1-' + Date.now(),
      context: { rawBody: 'Non-blocking test message with enough length.', metadata: { senderName: 'TC-G1', senderId: 'tc-g1-user' } }
    });
    const elapsed = Date.now() - start;
    assertTrue('TC-G1: handler returned in under 200ms', elapsed < 200);
  });

  // TC-G2: unreadable config file does not block turn.
  await runCase('TC-G2 unreadable config file', async () => {
    const sessionKey = 'tc-g2-' + Date.now();
    writeConfig({ extraction_timeout_ms: 2000 });
    fs.chmodSync(CONFIG_PATH, 0o000);
    process.env.EXTRACTION_SCRIPT_PATH_OVERRIDE = mocks.sleep3;
    delete process.env.EXTRACTION_TIMEOUT_MS_OVERRIDE;
    await cleanupSession(sessionKey);
    const start = Date.now();
    const cap = captureLogs();
    await callHandler(handler, {
      type: 'message', action: 'received', sessionKey,
      context: { rawBody: 'Unreadable config test message with enough length.', metadata: { senderName: 'TC-G2', senderId: 'tc-g2-user' } }
    });
    await new Promise(r => setTimeout(r, 3800));
    const elapsed = Date.now() - start;
    cap.restore();
    fs.chmodSync(CONFIG_PATH, 0o644);
    const cnt = await psql(`SELECT COUNT(*) FROM extraction_failures WHERE session_key = '${sessionKey}';`);
    assert('TC-G2: no dead-letter row (default > 2s)', '0', cnt);
    assertTrue('TC-G2: handler returned promptly', elapsed < 5000);
    await cleanupSession(sessionKey);
  });

  // Summary
  log(`\n=== Summary ===`);
  log(`PASS: ${PASS.length}`);
  log(`FAIL: ${FAIL.length}`);
  if (FAIL.length > 0) {
    log('Failed assertions:');
    FAIL.forEach(f => log(`  - ${f}`));
  }
  log(`Finished at ${new Date().toISOString()}`);
  process.exit(FAIL.length > 0 ? 1 : 0);
}

main().catch(err => {
  log(`FATAL: ${err.message}\n${err.stack}`);
  process.exit(1);
});
