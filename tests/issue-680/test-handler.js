#!/usr/bin/env node
// test-handler.js — Integration tests for issue #680 handler changes.
// Compiles memory/hooks/memory-extract/handler.ts and verifies the new
// exit-code 3 -> failure_reason='timeout_retries_exhausted' path and the
// EXTRACTION_ENABLE_RETRY env flag injection.

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
const COMPILE_DIR = fs.mkdtempSync('/tmp/issue680-handler-');
const HANDLER_JS = path.join(COMPILE_DIR, 'handler.js');
const MOCKS_DIR = fs.mkdtempSync('/tmp/issue680-mocks-');
const LOG_FILE = process.argv[2] || '/tmp/issue680-handler-test.log';

process.env.PGDATABASE = TEST_PGDATABASE;
process.env.PGUSER = TEST_PGUSER_DDL;
process.env.PGHOST = TEST_PGHOST;
delete process.env.PGPASSWORD;

const PASS = [];
const FAIL = [];

function log(...args) {
  const line = `[issue-680:handler] ${args.join(' ')}`;
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

function captureLogs() {
  const logs = [];
  const orig = {
    info: console.info,
    error: console.error,
    warn: console.warn,
    debug: console.debug,
    log: console.log
  };
  for (const level of Object.keys(orig)) {
    console[level] = (...a) => logs.push([level.toUpperCase(), a.map(x => typeof x === 'object' ? JSON.stringify(x) : String(x)).join(' ')]);
  }
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
  // Exit 3 simulates extract_memories.py after all retry attempts exhausted.
  retriesExhausted: writeMock('retriesExhausted', `
import sys
sys.stdin.read()
sys.stderr.write('LLM attempt 3/3 failed: timeout; retries exhausted\\n')
sys.exit(3)
`),
  // Writes env vars to a temp file so we can verify EXTRACTION_ENABLE_RETRY is set.
  envReporter: writeMock('envReporter', `
import os, sys, json
sys.stdin.read()
env = {k: os.environ.get(k, '') for k in ['EXTRACTION_ENABLE_RETRY', 'SENDER_NAME', 'OPENROUTER_API_KEY']}
with open(os.environ.get('ISSUE680_ENV_REPORT_PATH', '/tmp/issue680-env-report.json'), 'w') as f:
    json.dump(env, f)
sys.exit(0)
`),
  // Simulates a JSON parse failure (exit 2).
  jsonParseFailure: writeMock('jsonParseFailure', `
import sys
sys.stdin.read()
sys.stderr.write('Failed to parse LLM response as JSON\\n')
sys.exit(2)
`),
  // Simulates a quick nonzero exit (exit 1).
  nonzeroExit: writeMock('nonzeroExit', `
import sys
sys.stdin.read()
sys.stderr.write('deterministic error\\n')
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

  const handler = require(HANDLER_JS).default;

  // TC-H1: exit 3 -> timeout_retries_exhausted dead-letter
  await runCase('TC-H1 exit 3 -> timeout_retries_exhausted', async () => {
    const sessionKey = 'tc-h1-' + Date.now();
    process.env.EXTRACTION_SCRIPT_PATH_OVERRIDE = mocks.retriesExhausted;
    delete process.env.EXTRACTION_TIMEOUT_MS_OVERRIDE;
    await cleanupSession(sessionKey);
    const cap = captureLogs();
    await callHandler(handler, {
      type: 'message', action: 'received', sessionKey,
      context: { rawBody: 'This is a retry exhaustion test message with enough length.', metadata: { senderName: 'TC-H1', senderId: 'tc-h1-user' } }
    });
    cap.restore();
    const ok = await waitForDeadLetter(sessionKey);
    assert('TC-H1: dead-letter row written', true, ok);
    const row = await psql(`SELECT exit_code, failure_reason, stderr_tail FROM extraction_failures WHERE session_key = '${sessionKey}';`);
    const [exitCode, reason, stderr] = row.split('|');
    assert('TC-H1: exit_code = 3', '3', exitCode);
    assert('TC-H1: failure_reason = timeout_retries_exhausted', 'timeout_retries_exhausted', reason);
    assertContains('TC-H1: stderr tail contains retry exhausted', stderr, 'retries exhausted');
    assertContains('TC-H1: failure log contains reason', cap.text(), 'timeout_retries_exhausted');
    await cleanupSession(sessionKey);
  });

  // TC-H2: EXTRACTION_ENABLE_RETRY is passed to child env
  await runCase('TC-H2 EXTRACTION_ENABLE_RETRY env flag', async () => {
    const sessionKey = 'tc-h2-' + Date.now();
    const envReportPath = path.join('/tmp', `issue680-env-report-${sessionKey}.json`);
    process.env.EXTRACTION_SCRIPT_PATH_OVERRIDE = mocks.envReporter;
    process.env.ISSUE680_ENV_REPORT_PATH = envReportPath;
    delete process.env.EXTRACTION_TIMEOUT_MS_OVERRIDE;
    await cleanupSession(sessionKey);
    const cap = captureLogs();
    await callHandler(handler, {
      type: 'message', action: 'received', sessionKey,
      context: { rawBody: 'This is an env flag test message with enough length.', metadata: { senderName: 'TC-H2', senderId: 'tc-h2-user' } }
    });
    cap.restore();
    const cnt = await psql(`SELECT COUNT(*) FROM extraction_failures WHERE session_key = '${sessionKey}';`);
    assert('TC-H2: no dead-letter row on exit 0', '0', cnt);
    // Give the child a moment to write the report file.
    await new Promise(r => setTimeout(r, 300));
    let envReport = {};
    try {
      envReport = JSON.parse(fs.readFileSync(envReportPath, 'utf8'));
    } catch (e) {
      log(`TC-H2: could not read env report: ${e.message}`);
    }
    assert('TC-H2: EXTRACTION_ENABLE_RETRY=1 in child env', '1', envReport.EXTRACTION_ENABLE_RETRY || '');
    assert('TC-H2: SENDER_NAME passed to child env', 'TC-H2', envReport.SENDER_NAME || '');
    try { fs.unlinkSync(envReportPath); } catch (e) { /* ignore */ }
    delete process.env.ISSUE680_ENV_REPORT_PATH;
    await cleanupSession(sessionKey);
  });

  // TC-H3: JSON parse failure still maps to json_parse_failure
  await runCase('TC-H3 exit 2 -> json_parse_failure unchanged', async () => {
    const sessionKey = 'tc-h3-' + Date.now();
    process.env.EXTRACTION_SCRIPT_PATH_OVERRIDE = mocks.jsonParseFailure;
    delete process.env.EXTRACTION_TIMEOUT_MS_OVERRIDE;
    await cleanupSession(sessionKey);
    const cap = captureLogs();
    await callHandler(handler, {
      type: 'message', action: 'received', sessionKey,
      context: { rawBody: 'This is a JSON parse failure test message with enough length.', metadata: { senderName: 'TC-H3', senderId: 'tc-h3-user' } }
    });
    cap.restore();
    const ok = await waitForDeadLetter(sessionKey);
    assert('TC-H3: dead-letter row written', true, ok);
    const row = await psql(`SELECT exit_code, failure_reason FROM extraction_failures WHERE session_key = '${sessionKey}';`);
    const [exitCode, reason] = row.split('|');
    assert('TC-H3: exit_code = 2', '2', exitCode);
    assert('TC-H3: failure_reason = json_parse_failure', 'json_parse_failure', reason);
    await cleanupSession(sessionKey);
  });

  // TC-H4: deterministic nonzero exit still maps to nonzero_exit
  await runCase('TC-H4 exit 1 -> nonzero_exit unchanged', async () => {
    const sessionKey = 'tc-h4-' + Date.now();
    process.env.EXTRACTION_SCRIPT_PATH_OVERRIDE = mocks.nonzeroExit;
    delete process.env.EXTRACTION_TIMEOUT_MS_OVERRIDE;
    await cleanupSession(sessionKey);
    const cap = captureLogs();
    await callHandler(handler, {
      type: 'message', action: 'received', sessionKey,
      context: { rawBody: 'This is a nonzero exit test message with enough length.', metadata: { senderName: 'TC-H4', senderId: 'tc-h4-user' } }
    });
    cap.restore();
    const ok = await waitForDeadLetter(sessionKey);
    assert('TC-H4: dead-letter row written', true, ok);
    const row = await psql(`SELECT exit_code, failure_reason FROM extraction_failures WHERE session_key = '${sessionKey}';`);
    const [exitCode, reason] = row.split('|');
    assert('TC-H4: exit_code = 1', '1', exitCode);
    assert('TC-H4: failure_reason = nonzero_exit', 'nonzero_exit', reason);
    await cleanupSession(sessionKey);
  });

  // TC-H5: verify replay path does not set EXTRACTION_ENABLE_RETRY
  await runCase('TC-H5 replay path stays single-shot', async () => {
    const replayPath = path.join(REPO_ROOT, 'memory/scripts/extraction-replay.sh');
    const src = fs.readFileSync(replayPath, 'utf8');
    assertNotContains('TC-H5: replay does not enable retry', src, 'EXTRACTION_ENABLE_RETRY');
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

main().catch(err => {
  log(`FATAL: ${err.message}\n${err.stack}`);
  process.exit(1);
});
