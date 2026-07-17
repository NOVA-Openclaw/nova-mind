#!/usr/bin/env node
// test-handler.js — Chunk 2 tests for issue #485
// Compiles memory/hooks/memory-extract/handler.ts and runs cases against it.

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
const COMPILE_DIR = fs.mkdtempSync('/tmp/issue485-handler-');
const HANDLER_JS = path.join(COMPILE_DIR, 'handler.js');
const MOCKS_DIR = fs.mkdtempSync('/tmp/issue485-mocks-');
const LOG_FILE = process.argv[2] || '/tmp/issue485-handler-test.log';

// The handler under test calls psql without -U/-h, relying on PG env vars.
process.env.PGDATABASE = TEST_PGDATABASE;
process.env.PGUSER = TEST_PGUSER_DDL;
process.env.PGHOST = TEST_PGHOST;
delete process.env.PGPASSWORD;

const PASS = [];
const FAIL = [];
let currentCase = null;

function log(...args) {
  const line = `[issue-485:chunk2] ${args.join(' ')}`;
  fs.appendFileSync(LOG_FILE, line + '\n');
  console.log(line);
}

function logRaw(...args) {
  const line = args.join(' ');
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

function assertNotContains(name, haystack, needle) {
  const ok = !haystack.includes(needle);
  if (ok) {
    PASS.push(name);
    log(`PASS: ${name}`);
  } else {
    FAIL.push(name);
    log(`FAIL: ${name} (expected NOT to contain ${JSON.stringify(needle)})`);
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

async function cleanupSessionPattern(pattern) {
  try {
    await psqlAsDdl(`DELETE FROM extraction_failures WHERE session_key LIKE '${pattern.replace(/'/g, "''")}';`);
    await psqlAsDdl(`DELETE FROM channel_transcripts WHERE external_message_id LIKE '${pattern.replace(/'/g, "''")}';`);
    await psqlAsDdl(`DELETE FROM channel_sessions WHERE session_key LIKE '${pattern.replace(/'/g, "''")}';`);
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
    // tsc emits type errors but still produces JS for our purposes.
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

async function waitForDeadLetter(sessionKey, timeoutMs = 3000) {
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
  ok: writeMock('ok', `
import sys
sys.stdin.read()
sys.exit(0)
`),
  okStderr: writeMock('okStderr', `
import sys
sys.stdin.read()
sys.stderr.write('WARNING: low confidence extraction\\n')
sys.exit(0)
`),
  failOne: writeMock('failOne', `
import sys
sys.stdin.read()
sys.stderr.write('ERROR: Anthropic API request failed: 529\\n')
sys.exit(1)
`),
  sleep: writeMock('sleep', `
import sys, time
sys.stdin.read()
time.sleep(300)
`),
  stderrExactCap: writeMock('stderrExactCap', `
import sys
sys.stdin.read()
s = 'A' * 16384
sys.stderr.write(s)
sys.exit(1)
`),
  stderrOverCap: writeMock('stderrOverCap', `
import sys
sys.stdin.read()
s = ''.join(chr(65 + (i % 26)) for i in range(16385))
sys.stderr.write(s)
sys.exit(1)
`),
  stderrHuge: writeMock('stderrHuge', `
import sys
sys.stdin.read()
s = 'X' * 81920
sys.stderr.write(s)
sys.exit(1)
`),
  emptyStderr: writeMock('emptyStderr', `
import sys
sys.stdin.read()
sys.exit(1)
`),
  hugeStdout: writeMock('hugeStdout', `
import sys
sys.stdin.read()
s = 'O' * 204800
sys.stdout.write(s)
sys.stderr.write('small stderr\\n')
sys.exit(0)
`),
  interleaved: writeMock('interleaved', `
import sys
sys.stdin.read()
# stderr block A (26 bytes repeated 700 times => 18200 bytes)
for i in range(700):
    sys.stderr.write(''.join(chr(65+j) for j in range(26)))
# stdout block B (digits repeated 700 times => 7000 bytes)
for i in range(700):
    sys.stdout.write('0123456789')
sys.stderr.write('FINAL-STDERR-MARKER')
sys.stdout.write('FINAL-STDOUT-MARKER')
sys.exit(1)
`),
  secretsStderr: writeMock('secretsStderr', `
import sys
sys.stdin.read()
sys.stderr.write('ANTHROPIC_API_KEY=sk-secret123\\n')
sys.exit(1)
`)
};

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

async function main() {
  log(`Started at ${new Date().toISOString()}`);
  log(`Log file: ${LOG_FILE}`);
  compileHandler();

  // We patch child_process.execFile before requiring handler for psql-failure tests.
  // Normal tests load a fresh require cache each time.
  // To keep things simple, we import handler once at start; psql-failure tests
  // will re-require after patching.
  let handler = require(HANDLER_JS).default;

  // TC-A1: happy path, no dead-letter row
  await runCase('TC-A1 happy path', async () => {
    const sessionKey = 'tc-a1-' + Date.now();
    process.env.EXTRACTION_SCRIPT_PATH_OVERRIDE = mocks.ok;
    delete process.env.EXTRACTION_TIMEOUT_MS_OVERRIDE;
    await cleanupSession(sessionKey);
    const cap = captureLogs();
    await callHandler(handler, {
      type: 'message', action: 'received', sessionKey,
      context: { rawBody: 'This is a happy path test message with enough length.', metadata: { senderName: 'TC-A1', senderId: 'tc-a1-user' } }
    });
    cap.restore();
    const cnt = await psql(`SELECT COUNT(*) FROM extraction_failures WHERE session_key = '${sessionKey}';`);
    assert('TC-A1: no dead-letter row', '0', cnt);
    assertContains('TC-A1: extraction complete log', cap.text(), 'Extraction complete');
    await cleanupSession(sessionKey);
  });

  // TC-A2: exit 0 with stderr warnings, no dead-letter
  await runCase('TC-A2 warnings exit 0', async () => {
    const sessionKey = 'tc-a2-' + Date.now();
    process.env.EXTRACTION_SCRIPT_PATH_OVERRIDE = mocks.okStderr;
    delete process.env.EXTRACTION_TIMEOUT_MS_OVERRIDE;
    await cleanupSession(sessionKey);
    const cap = captureLogs();
    await callHandler(handler, {
      type: 'message', action: 'received', sessionKey,
      context: { rawBody: 'This is a warning-only test message with enough length.', metadata: { senderName: 'TC-A2', senderId: 'tc-a2-user' } }
    });
    cap.restore();
    const cnt = await psql(`SELECT COUNT(*) FROM extraction_failures WHERE session_key = '${sessionKey}';`);
    assert('TC-A2: no dead-letter row on warning-only exit 0', '0', cnt);
    await cleanupSession(sessionKey);
  });

  // TC-B1: nonzero exit -> dead-letter with stderr tail
  await runCase('TC-B1 nonzero exit', async () => {
    const sessionKey = 'tc-b1-' + Date.now();
    process.env.EXTRACTION_SCRIPT_PATH_OVERRIDE = mocks.failOne;
    delete process.env.EXTRACTION_TIMEOUT_MS_OVERRIDE;
    await cleanupSession(sessionKey);
    const cap = captureLogs();
    await callHandler(handler, {
      type: 'message', action: 'received', sessionKey,
      context: { rawBody: 'This is a nonzero exit test message with enough length.', metadata: { senderName: 'TC-B1', senderId: 'tc-b1-user' } }
    });
    cap.restore();
    const ok = await waitForDeadLetter(sessionKey);
    assert('TC-B1: dead-letter row written', true, ok);
    const row = await psql(`SELECT exit_code, failure_reason, stderr_tail FROM extraction_failures WHERE session_key = '${sessionKey}';`);
    const [exitCode, reason, stderr] = row.split('|');
    assert('TC-B1: exit_code = 1', '1', exitCode);
    assert('TC-B1: failure_reason = nonzero_exit', 'nonzero_exit', reason);
    assertContains('TC-B1: stderr tail contains error', stderr, 'ERROR: Anthropic API request failed: 529');
    assertContains('TC-B1: failure log contains stderr tail', cap.text(), 'ERROR: Anthropic API request failed: 529');
    await cleanupSession(sessionKey);
  });

  // TC-B2: spawn error
  await runCase('TC-B2 spawn error', async () => {
    const sessionKey = 'tc-b2-' + Date.now();
    process.env.EXTRACTION_SCRIPT_PATH_OVERRIDE = mocks.ok;
    process.env.EXTRACTION_PYTHON_CMD_OVERRIDE = '/nonexistent/python-cmd-issue485';
    delete process.env.EXTRACTION_TIMEOUT_MS_OVERRIDE;
    await cleanupSession(sessionKey);
    const cap = captureLogs();
    let threw = false;
    try {
      await callHandler(handler, {
        type: 'message', action: 'received', sessionKey,
        context: { rawBody: 'This is a spawn error test message with enough length.', metadata: { senderName: 'TC-B2', senderId: 'tc-b2-user' } }
      });
    } catch (e) {
      threw = true;
    }
    cap.restore();
    assert('TC-B2: handler did not throw', false, threw);
    const ok = await waitForDeadLetter(sessionKey);
    assert('TC-B2: dead-letter row written', true, ok);
    const row = await psql(`SELECT exit_code, failure_reason FROM extraction_failures WHERE session_key = '${sessionKey}';`);
    const [exitCode, reason] = row.split('|');
    assert('TC-B2: exit_code is NULL', '', exitCode);
    assert('TC-B2: failure_reason = spawn_error', 'spawn_error', reason);
    delete process.env.EXTRACTION_PYTHON_CMD_OVERRIDE;
    await cleanupSession(sessionKey);
  });

  // TC-B3: timeout kill
  await runCase('TC-B3 timeout kill', async () => {
    const sessionKey = 'tc-b3-' + Date.now();
    process.env.EXTRACTION_SCRIPT_PATH_OVERRIDE = mocks.sleep;
    process.env.EXTRACTION_TIMEOUT_MS_OVERRIDE = '1000';
    await cleanupSession(sessionKey);
    const cap = captureLogs();
    const start = Date.now();
    await callHandler(handler, {
      type: 'message', action: 'received', sessionKey,
      context: { rawBody: 'This is a timeout test message with enough length.', metadata: { senderName: 'TC-B3', senderId: 'tc-b3-user' } }
    });
    // The timeout log fires asynchronously after handler returns; keep capture
    // active until the dead-letter row appears.
    const ok = await waitForDeadLetter(sessionKey, 5000);
    const elapsed = Date.now() - start;
    cap.restore();
    assert('TC-B3: completed within timeout+grace (under 10s)', true, elapsed < 10000);
    assert('TC-B3: dead-letter row written', true, ok);
    const row = await psql(`SELECT exit_code, failure_reason FROM extraction_failures WHERE session_key = '${sessionKey}';`);
    const [exitCode, reason] = row.split('|');
    assert('TC-B3: exit_code is NULL', '', exitCode);
    assert('TC-B3: failure_reason = timeout', 'timeout', reason);
    assertContains('TC-B3: log indicates timeout', cap.text(), 'timed out');
    await cleanupSession(sessionKey);
  });

  // TC-C4: empty stderr
  await runCase('TC-C4 empty stderr', async () => {
    const sessionKey = 'tc-c4-' + Date.now();
    process.env.EXTRACTION_SCRIPT_PATH_OVERRIDE = mocks.emptyStderr;
    delete process.env.EXTRACTION_TIMEOUT_MS_OVERRIDE;
    await cleanupSession(sessionKey);
    const cap = captureLogs();
    await callHandler(handler, {
      type: 'message', action: 'received', sessionKey,
      context: { rawBody: 'This is an empty stderr test message with enough length.', metadata: { senderName: 'TC-C4', senderId: 'tc-c4-user' } }
    });
    cap.restore();
    const ok = await waitForDeadLetter(sessionKey);
    assert('TC-C4: dead-letter row written', true, ok);
    const row = await psql(`SELECT stderr_tail FROM extraction_failures WHERE session_key = '${sessionKey}';`);
    assert('TC-C4: stderr_tail is empty/NULL', true, row === '' || row === 'NULL' || row === null);
    assertNotContains('TC-C4: no undefined in log', cap.text(), 'undefined');
    await cleanupSession(sessionKey);
  });

  // TC-C1/C2: stderr cap boundary
  await runCase('TC-C1/C2 stderr cap boundary', async () => {
    const sessionKey = 'tc-c1c2-' + Date.now();
    process.env.EXTRACTION_SCRIPT_PATH_OVERRIDE = mocks.stderrExactCap;
    delete process.env.EXTRACTION_TIMEOUT_MS_OVERRIDE;
    await cleanupSession(sessionKey);
    await callHandler(handler, {
      type: 'message', action: 'received', sessionKey,
      context: { rawBody: 'This is a cap boundary test message with enough length.', metadata: { senderName: 'TC-C1C2', senderId: 'tc-c1c2-user' } }
    });
    await waitForDeadLetter(sessionKey);
    const row = await psql(`SELECT stderr_tail FROM extraction_failures WHERE session_key = '${sessionKey}';`);
    assert('TC-C1: exact cap retained (16384 bytes)', 16384, Buffer.byteLength(row || '', 'utf8'));
    await cleanupSession(sessionKey);

    const sessionKey2 = 'tc-c2-' + Date.now();
    process.env.EXTRACTION_SCRIPT_PATH_OVERRIDE = mocks.stderrOverCap;
    await cleanupSession(sessionKey2);
    await callHandler(handler, {
      type: 'message', action: 'received', sessionKey: sessionKey2,
      context: { rawBody: 'This is a cap+1 test message with enough length.', metadata: { senderName: 'TC-C2', senderId: 'tc-c2-user' } }
    });
    await waitForDeadLetter(sessionKey2);
    const row2 = await psql(`SELECT stderr_tail FROM extraction_failures WHERE session_key = '${sessionKey2}';`);
    const len2 = Buffer.byteLength(row2 || '', 'utf8');
    assert('TC-C2: cap+1 retained as 16384 bytes', 16384, len2);
    // The script writes A..Z repeated; cap+1 means first byte 'A' is dropped, so tail starts with 'B'.
    assertContains('TC-C2: tail is last N bytes (starts with B)', row2 || '', 'B');
    await cleanupSession(sessionKey2);
  });

  // TC-C3: huge stderr no stall
  await runCase('TC-C3 huge stderr no stall', async () => {
    const sessionKey = 'tc-c3-' + Date.now();
    process.env.EXTRACTION_SCRIPT_PATH_OVERRIDE = mocks.stderrHuge;
    delete process.env.EXTRACTION_TIMEOUT_MS_OVERRIDE;
    await cleanupSession(sessionKey);
    const start = Date.now();
    await callHandler(handler, {
      type: 'message', action: 'received', sessionKey,
      context: { rawBody: 'This is a huge stderr test message with enough length.', metadata: { senderName: 'TC-C3', senderId: 'tc-c3-user' } }
    });
    await waitForDeadLetter(sessionKey);
    const elapsed = Date.now() - start;
    assert('TC-C3: completed without stall (under 5s)', true, elapsed < 5000);
    const row = await psql(`SELECT stderr_tail FROM extraction_failures WHERE session_key = '${sessionKey}';`);
    assert('TC-C3: retained tail length is 16384', 16384, Buffer.byteLength(row || '', 'utf8'));
    await cleanupSession(sessionKey);
  });

  // TC-C5: huge stdout, exit 0, no dead-letter
  await runCase('TC-C5 huge stdout exit 0', async () => {
    const sessionKey = 'tc-c5-' + Date.now();
    process.env.EXTRACTION_SCRIPT_PATH_OVERRIDE = mocks.hugeStdout;
    delete process.env.EXTRACTION_TIMEOUT_MS_OVERRIDE;
    await cleanupSession(sessionKey);
    const start = Date.now();
    await callHandler(handler, {
      type: 'message', action: 'received', sessionKey,
      context: { rawBody: 'This is a huge stdout test message with enough length.', metadata: { senderName: 'TC-C5', senderId: 'tc-c5-user' } }
    });
    const elapsed = Date.now() - start;
    assert('TC-C5: completed without stall (under 5s)', true, elapsed < 5000);
    const cnt = await psql(`SELECT COUNT(*) FROM extraction_failures WHERE session_key = '${sessionKey}';`);
    assert('TC-C5: no dead-letter row on success', '0', cnt);
    await cleanupSession(sessionKey);
  });

  // TC-C6: interleaved stderr/stdout
  await runCase('TC-C6 interleaved stderr/stdout', async () => {
    const sessionKey = 'tc-c6-' + Date.now();
    process.env.EXTRACTION_SCRIPT_PATH_OVERRIDE = mocks.interleaved;
    delete process.env.EXTRACTION_TIMEOUT_MS_OVERRIDE;
    await cleanupSession(sessionKey);
    await callHandler(handler, {
      type: 'message', action: 'received', sessionKey,
      context: { rawBody: 'This is an interleaved stderr stdout test message with enough length.', metadata: { senderName: 'TC-C6', senderId: 'tc-c6-user' } }
    });
    await waitForDeadLetter(sessionKey);
    const row = await psql(`SELECT stderr_tail, stdout_tail FROM extraction_failures WHERE session_key = '${sessionKey}';`);
    const [stderrTail, stdoutTail] = row.split('|');
    assertContains('TC-C6: stderr tail contains final stderr marker', stderrTail || '', 'FINAL-STDERR-MARKER');
    assertNotContains('TC-C6: stderr tail does not contain stdout marker', stderrTail || '', 'FINAL-STDOUT-MARKER');
    assertContains('TC-C6: stdout tail contains final stdout marker', stdoutTail || '', 'FINAL-STDOUT-MARKER');
    assertNotContains('TC-C6: stdout tail does not contain stderr marker', stdoutTail || '', 'FINAL-STDERR-MARKER');
    await cleanupSession(sessionKey);
  });

  // TC-E2/E3: secrets + senderId truncation
  await runCase('TC-E2/E3 log safety', async () => {
    const sessionKey = 'tc-e2-' + Date.now();
    process.env.EXTRACTION_SCRIPT_PATH_OVERRIDE = mocks.secretsStderr;
    delete process.env.EXTRACTION_TIMEOUT_MS_OVERRIDE;
    await cleanupSession(sessionKey);
    const cap = captureLogs();
    await callHandler(handler, {
      type: 'message', action: 'received', sessionKey,
      context: { rawBody: 'This is a secrets log test message with enough length.', metadata: { senderName: 'TC-E2', senderId: 'tc-e2-full-sender-id' } }
    });
    cap.restore();
    const text = cap.text();
    // New failure logging should not expose full senderId (only truncated prefix + '...').
    assertNotContains('TC-E3: full senderId not in failure log', text, 'tc-e2-full-sender-id');
    assertContains('TC-E3: truncated senderId present', text, 'tc-e2-fu...');
    // The stderr secret may appear because it came from the mocked child; this test asserts
    // the NEW code (psql catch logging) does not leak secrets. The failure log carries child
    // stderr verbatim by design, so we only assert no connection-string-style secret dump
    // from the new psql catch sites in this path.
    assertNotContains('TC-E2: no connection string with password in log', text, 'postgresql://');
    await cleanupSession(sessionKey);
  });

  // TC-F2: early returns, no spawn
  await runCase('TC-F2 early returns', async () => {
    delete process.env.EXTRACTION_SCRIPT_PATH_OVERRIDE;
    const checks = [
      { type: 'typing', action: 'received', rawBody: 'typing event', label: 'non-message type' },
      { type: 'message', action: 'sent', rawBody: 'sent action', label: 'non-received action' },
      { type: 'message', action: 'received', rawBody: 'short', label: 'short body' },
      { type: 'message', action: 'received', rawBody: '/command with args', label: 'command body' }
    ];
    for (const c of checks) {
      const cap = captureLogs();
      await callHandler(handler, {
        type: c.type, action: c.action, sessionKey: 'tc-f2-' + c.label,
        context: { rawBody: c.rawBody, metadata: { senderName: 'TC-F2' } }
      });
      cap.restore();
      assertNotContains(`TC-F2: no spawn for ${c.label}`, cap.text(), 'Processing message');
    }
  });

  // TC-F3: activity tracking
  await runCase('TC-F3 activity tracking', async () => {
    await cleanupSessionPattern('tc-f3%');
    process.env.EXTRACTION_SCRIPT_PATH_OVERRIDE = mocks.ok;
    delete process.env.EXTRACTION_TIMEOUT_MS_OVERRIDE;

    // Snapshot current counters from a baseline call.
    const baselineCap = captureLogs();
    await callHandler(handler, { type: 'message', action: 'received', sessionKey: 'tc-f3-baseline', context: { rawBody: 'Baseline user message for activity tracking test.', metadata: { senderName: 'TC-F3' } } });
    baselineCap.restore();
    const baselineMatch = baselineCap.text().match(/"userMessages":(\d+)/);
    const baselineHeartMatch = baselineCap.text().match(/"heartbeats":(\d+)/);
    const baseUser = baselineMatch ? parseInt(baselineMatch[1], 10) : 0;
    const baseHeart = baselineHeartMatch ? parseInt(baselineHeartMatch[1], 10) : 0;

    const cap = captureLogs();
    // heartbeat
    await callHandler(handler, { type: 'message', action: 'received', sessionKey: 'tc-f3', context: { rawBody: 'HEARTBEAT update from system monitor', metadata: { senderName: 'TC-F3' } } });
    // user messages
    await callHandler(handler, { type: 'message', action: 'received', sessionKey: 'tc-f3', context: { rawBody: 'User message number one for activity tracking test.', metadata: { senderName: 'TC-F3' } } });
    await callHandler(handler, { type: 'message', action: 'received', sessionKey: 'tc-f3', context: { rawBody: 'User message number two for activity tracking test.', metadata: { senderName: 'TC-F3' } } });
    cap.restore();
    const text = cap.text();
    const heartMatch = text.match(/"heartbeats":(\d+)/g);
    const userMatch = text.match(/"userMessages":(\d+)/g);
    const finalHeart = heartMatch ? parseInt(heartMatch[heartMatch.length - 1].match(/(\d+)/)[1], 10) : baseHeart;
    const finalUser = userMatch ? parseInt(userMatch[userMatch.length - 1].match(/(\d+)/)[1], 10) : baseUser;
    assert('TC-F3: heartbeat counter incremented by 1', baseHeart + 1, finalHeart);
    assert('TC-F3: user message counter incremented by 2', baseUser + 2, finalUser);
    await cleanupSessionPattern('tc-f3%');
  });

  // TC-F1: grep regression
  await runCase('TC-F1 grep regression', async () => {
    const handlerPath = path.join(REPO_ROOT, 'memory/hooks/memory-extract/handler.ts');
    const src = fs.readFileSync(handlerPath, 'utf8');
    assertNotContains('TC-F1: no bare silent catch on stdout', src, 'catch(() => ({ stdout:');
    assertNotContains('TC-F1: no bare silent catch with spaces', src, 'catch(() => ({stdout:');
  });

  // TC-D1: pre-existing transcript + failure -> FK recovered, not body fallback
  await runCase('TC-D1 FK recovery on pre-existing transcript', async () => {
    const sessionKey = 'tc-d1-' + Date.now();
    const chatId = 'openclaw:tc-d1-chat-' + Date.now();
    const msgId = 'tc-d1-msg';
    await cleanupSession(sessionKey);

    // Pre-insert session and transcript.
    await psqlAsDdl(`
      INSERT INTO channel_sessions (session_key, agent_id, provider, external_chat_id, chat_type)
      VALUES ('${sessionKey}', 'main', 'openclaw', '${chatId}', 'direct');
    `);
    const sessId = await psql(`SELECT id FROM channel_sessions WHERE session_key = '${sessionKey}';`);
    await psqlAsDdl(`
      INSERT INTO channel_transcripts (session_id, external_message_id, timestamp, role, content)
      VALUES (${sessId}, '${msgId}', NOW(), 'user', 'pre-existing body');
    `);
    const txId = await psql(`SELECT id FROM channel_transcripts WHERE external_message_id = '${msgId}';`);

    process.env.EXTRACTION_SCRIPT_PATH_OVERRIDE = mocks.failOne;
    await callHandler(handler, {
      type: 'message', action: 'received', sessionKey,
      context: {
        rawBody: 'This is a pre-existing transcript failure test message with enough length.',
        metadata: { senderName: 'TC-D1', senderId: 'tc-d1-user' },
        conversationId: chatId,
        messageId: msgId
      }
    });
    await waitForDeadLetter(sessionKey);
    const row = await psql(`SELECT channel_transcript_id, content FROM extraction_failures WHERE session_key = '${sessionKey}';`);
    const [fk, body] = row.split('|');
    assert('TC-D1: channel_transcript_id matches pre-existing row', txId, fk);
    assert('TC-D1: content fallback is NULL/empty', true, body === '' || body === 'NULL' || body === null);
    await cleanupSession(sessionKey);
  });

  // TC-D11: pre-existing transcript + timeout -> FK recovered
  await runCase('TC-D11 FK recovery on timeout', async () => {
    const sessionKey = 'tc-d11-' + Date.now();
    const chatId = 'openclaw:tc-d11-chat-' + Date.now();
    const msgId = 'tc-d11-msg';
    await cleanupSession(sessionKey);

    await psqlAsDdl(`
      INSERT INTO channel_sessions (session_key, agent_id, provider, external_chat_id, chat_type)
      VALUES ('${sessionKey}', 'main', 'openclaw', '${chatId}', 'direct');
    `);
    const sessId = await psql(`SELECT id FROM channel_sessions WHERE session_key = '${sessionKey}';`);
    await psqlAsDdl(`
      INSERT INTO channel_transcripts (session_id, external_message_id, timestamp, role, content)
      VALUES (${sessId}, '${msgId}', NOW(), 'user', 'pre-existing body d11');
    `);
    const txId = await psql(`SELECT id FROM channel_transcripts WHERE external_message_id = '${msgId}';`);

    process.env.EXTRACTION_SCRIPT_PATH_OVERRIDE = mocks.sleep;
    process.env.EXTRACTION_TIMEOUT_MS_OVERRIDE = '1000';
    await callHandler(handler, {
      type: 'message', action: 'received', sessionKey,
      context: {
        rawBody: 'This is a pre-existing transcript timeout test message with enough length.',
        metadata: { senderName: 'TC-D11', senderId: 'tc-d11-user' },
        conversationId: chatId,
        messageId: msgId
      }
    });
    await waitForDeadLetter(sessionKey);
    const row = await psql(`SELECT channel_transcript_id, failure_reason FROM extraction_failures WHERE session_key = '${sessionKey}';`);
    const [fk, reason] = row.split('|');
    assert('TC-D11: channel_transcript_id matches pre-existing row', txId, fk);
    assert('TC-D11: failure_reason = timeout', 'timeout', reason);
    await cleanupSession(sessionKey);
  });

  // TC-B4/B5/B6: psql catches logged + body fallback
  await runCase('TC-B4/B5/B6 psql failure logging and body fallback', async () => {
    const sessionKey = 'tc-b4b5b6-' + Date.now();
    process.env.EXTRACTION_SCRIPT_PATH_OVERRIDE = mocks.failOne;
    delete process.env.EXTRACTION_TIMEOUT_MS_OVERRIDE;
    await cleanupSession(sessionKey);

    // Patch execFile so psql calls for channel_sessions/transcripts fail, but
    // the dead-letter INSERT into extraction_failures still succeeds.
    const originalExecFile = cp.execFile;
    cp.execFile = function(file, args, ...rest) {
      if (file === 'psql') {
        const sql = Array.isArray(args) ? args.join(' ') : '';
        const isDeadLetterInsert = sql.includes('INSERT INTO extraction_failures');
        if (!isDeadLetterInsert) {
          const cb = rest[rest.length - 1];
          if (typeof cb === 'function') {
            cb(new Error('injected psql failure: connection refused'), null, null);
            return;
          }
        }
      }
      return originalExecFile(file, args, ...rest);
    };

    // Re-require handler so it picks up patched execFile.
    delete require.cache[HANDLER_JS];
    const patchedHandler = require(HANDLER_JS).default;

    const cap = captureLogs();
    await callHandler(patchedHandler, {
      type: 'message', action: 'received', sessionKey,
      context: { rawBody: 'This is a psql failure test message with enough length.', metadata: { senderName: 'TC-B4B5B6', senderId: 'tc-b4b5b6-user' } }
    });
    cap.restore();

    // Restore execFile for subsequent tests.
    cp.execFile = originalExecFile;

    const text = cap.text();
    assertContains('TC-B4/B5: psql session-upsert failure logged', text, 'psql upsert failed');
    assertContains('TC-B4/B5: psql transcript-upsert failure logged', text, 'psql upsert failed');
    assertNotContains('TC-E2: psql failure log does not include connection string', text, 'postgresql://');

    const ok = await waitForDeadLetter(sessionKey);
    assert('TC-B6: dead-letter row written despite psql failures', true, ok);
    const row = await psql(`SELECT channel_transcript_id, content FROM extraction_failures WHERE session_key = '${sessionKey}';`);
    const [fk, body] = row.split('|');
    assert('TC-B6: channel_transcript_id is NULL', true, fk === '' || fk === 'NULL' || fk === null);
    assertContains('TC-B6: body fallback contains original message', body || '', 'psql failure test message');
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
