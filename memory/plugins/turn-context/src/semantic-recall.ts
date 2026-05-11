/**
 * Semantic Recall subsystem.
 *
 * Spawns proactive-recall.py asynchronously (NEVER spawnSync — that freezes
 * the event loop) and returns formatted memory context for injection.
 *
 * Ported from ~/.openclaw/hooks/semantic-recall/handler.ts
 * Root cause being fixed: the old hook used spawnSync which blocked the
 * entire Node.js event loop on every message.
 *
 * Issue: nova-mind #182
 */

import { spawn } from "child_process";
import { existsSync } from "fs";
import * as os from "os";
import { join } from "path";

// ── Python interpreter selection ──────────────────────────────────────────────

const username = os.userInfo().username;
const STANDARD_VENV = join(
  os.homedir(),
  ".local",
  "share",
  username,
  "venv",
  "bin",
  "python"
);
const WORKSPACE_VENV = join(
  os.homedir(),
  ".openclaw",
  "scripts",
  "tts-venv",
  "bin",
  "python"
);

const PYTHON_BIN = existsSync(STANDARD_VENV) ? STANDARD_VENV : WORKSPACE_VENV;

// ── Script path ───────────────────────────────────────────────────────────────

const RECALL_SCRIPT = join(os.homedir(), ".openclaw", "scripts", "proactive-recall.py");

// ── Configuration ─────────────────────────────────────────────────────────────

const TOKEN_BUDGET = parseInt(
  process.env.SEMANTIC_RECALL_TOKEN_BUDGET || "1000",
  10
);
const HIGH_CONFIDENCE_THRESHOLD = parseFloat(
  process.env.SEMANTIC_RECALL_HIGH_CONFIDENCE || "0.7"
);
const SPAWN_TIMEOUT_MS = 5000; // 5 seconds

// ── Types ─────────────────────────────────────────────────────────────────────

interface RecallMemory {
  source: string;
  content: string;
  similarity: number;
  full?: boolean;
}

interface RecallResult {
  memories?: RecallMemory[];
  tokens_used?: number;
  token_budget?: number;
}

// ── Public API ────────────────────────────────────────────────────────────────

export interface RecallInput {
  content: string;
  senderId?: string;
  senderName?: string;
  provider?: string;
  conversationId?: string;
  isGroup?: boolean;
  channelName?: string;
  guildId?: string;
  messageId?: string;
}

/**
 * Run proactive-recall.py asynchronously and return formatted memory context,
 * or null if recall fails or finds nothing.
 *
 * Uses async spawn (child_process.spawn wrapped in a Promise) so the Node.js
 * event loop is NEVER blocked.
 *
 * Sends a JSON payload via stdin (no --stdin flag; proactive-recall.py reads
 * JSON from stdin when no positional args are given).
 */
export async function runSemanticRecall(
  input: RecallInput
): Promise<string | null> {
  const messageText = input.content.substring(0, 2000);

  const stdinPayload = JSON.stringify({
    content: messageText,
    senderId: input.senderId ?? '',
    senderName: input.senderName ?? '',
    provider: input.provider ?? '',
    conversationId: input.conversationId ?? '',
    isGroup: input.isGroup ?? false,
    channelName: input.channelName ?? '',
    guildId: input.guildId ?? '',
    messageId: input.messageId ?? '',
  });

  let result: RecallResult | null = null;
  try {
    result = await spawnWithTimeout(stdinPayload);
  } catch (err) {
    console.error(
      "[turn-context] Semantic recall error:",
      err instanceof Error ? err.message : String(err)
    );
    return null;
  }

  if (!result?.memories || result.memories.length === 0) {
    return null;
  }

  // Format memories with tiered confidence indicators
  const memoryLines = result.memories.map((m) => {
    const indicator = m.similarity >= HIGH_CONFIDENCE_THRESHOLD ? "🎯" : "📝";
    const pct = (m.similarity * 100).toFixed(0);
    return `${indicator} [${m.source}] (${pct}%): ${m.content}`;
  });

  const tokensInfo =
    result.tokens_used != null
      ? ` (~${result.tokens_used}/${result.token_budget} tokens)`
      : "";
  console.log(
    `[turn-context] Semantic recall found ${result.memories.length} memories${tokensInfo}`
  );

  return `🧠 **Relevant Context:**\n${memoryLines.join("\n\n")}`;
}

// ── Async spawn helper ────────────────────────────────────────────────────────

function spawnWithTimeout(stdinPayload: string): Promise<RecallResult> {
  return new Promise((resolve, reject) => {
    const child = spawn(
      PYTHON_BIN,
      [
        RECALL_SCRIPT,
        "--max-tokens",
        String(TOKEN_BUDGET),
        "--high-confidence",
        String(HIGH_CONFIDENCE_THRESHOLD),
      ],
      {
        env: { ...process.env },
        stdio: ["pipe", "pipe", "pipe"],
      }
    );

    let stdout = "";
    let stderr = "";

    child.stdout.on("data", (chunk: Buffer) => {
      stdout += chunk.toString();
    });

    child.stderr.on("data", (chunk: Buffer) => {
      stderr += chunk.toString();
    });

    // Hard timeout — kill the process if it hangs
    const timer = setTimeout(() => {
      child.kill("SIGTERM");
      reject(new Error(`proactive-recall.py timed out after ${SPAWN_TIMEOUT_MS}ms`));
    }, SPAWN_TIMEOUT_MS);

    child.on("close", (code) => {
      clearTimeout(timer);
      if (code === 0 && stdout) {
        try {
          resolve(JSON.parse(stdout) as RecallResult);
        } catch (parseErr) {
          reject(
            new Error(`Failed to parse recall output: ${parseErr}; stdout=${stdout.substring(0, 200)}`)
          );
        }
      } else {
        reject(
          new Error(
            `proactive-recall.py exited with code ${code}; stderr=${stderr.substring(0, 300)}`
          )
        );
      }
    });

    child.on("error", (err) => {
      clearTimeout(timer);
      reject(err);
    });

    // Write JSON payload to stdin and close it
    child.stdin.write(stdinPayload, "utf-8");
    child.stdin.end();
  });
}
