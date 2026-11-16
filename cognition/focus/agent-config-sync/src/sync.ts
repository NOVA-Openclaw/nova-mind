/**
 * Agent Config Sync — core logic
 *
 * Queries the `agents` table and builds the agents.json config as a keyed
 * object `{ "<id>": {...} }` matching the OpenClaw 2026.9.x
 * `agents.entries` schema. Writes atomically (tmp + rename) to prevent
 * partial reads, and validates the generated shape BEFORE promoting the temp
 * file so a hot-reload watcher can never pick up an invalid file.
 *
 * Also syncs HEARTBEAT.md files from `agent_bootstrap_context` to the correct
 * workspace directories for each agent.
 *
 * Schema contract (OpenClaw 2026.9.x):
 *   src/config/zod-schema.agents.ts:35-39 — entries is a z.record keyed by
 *   /^[a-z0-9_][a-z0-9_-]{0,63}$/i, values are AgentEntrySchema.omit({id:true})
 *   .extend({default: z.boolean().optional()}).
 */

import fs from "node:fs";
import path from "node:path";
import crypto from "node:crypto";
import type pg from "pg";

// ── Types ───────────────────────────────────────────────────────────────────

export type HeartbeatRow = {
  agent_name: string;
  content: string;
};

export type AgentRow = {
  name: string;
  model: string | null;
  fallback_models: string[] | string | null | unknown;
  thinking: string | null;
  instance_type: string;
  is_default: boolean | null;
  allowed_subagents: string[] | null;
  status?: string | null;
  // #262 — Per-agent heartbeat config (optional: present once DB migration applied)
  heartbeat_enabled?: boolean | null;
  heartbeat_every?: string | null;
  heartbeat_target?: string | null;
  heartbeat_to?: string | null;
  // #714 — propagate isolatedSession through agent-config-sync
  heartbeat_isolated_session?: boolean | null;
};

type HeartbeatConfig = { every?: string; target?: string; to?: string; isolatedSession?: boolean };

/** How the caller wants the default agent expressed in the emitted entries. */
export type OwnershipMode = "legacy" | "explicit";

/** Value shape for a single agent inside `agents.entries`.
 *
 * The legacy `default: true` marker is only emitted under `ownershipMode:
 * "legacy"` (OpenClaw 2026.9.x and earlier). Under `ownershipMode:
 * "explicit"` (OpenClaw 2026.11.3+) the system agent is determined by
 * `agents.defaults.systemAgent.agentId` and channel `bindings`; emitting the
 * marker there would make the gateway config invalid.
 */
export type AgentEntryConfig = {
  default?: true;
  model: string | { primary: string; fallbacks: string[] };
  thinkingDefault?: string;
  subagents?: { allowAgents: string[] };
  heartbeat?: HeartbeatConfig;
};

/** Options for `buildAgentsList()`. */
export type BuildAgentsListOptions = {
  /** "legacy" emits `default: true` for the default agent; "explicit" never does. */
  ownershipMode?: OwnershipMode;
  logger?: BuildLogger;
};

/** Result of `buildAgentsList()` — keyed entries plus any skipped rows. */
export type BuildAgentsListResult = {
  entries: Record<string, AgentEntryConfig>;
  skipped: Array<{ name: string; reason: string }>;
};

/** A single channel account that should route to the default agent. */
export type ChannelAccount = {
  channel: string;
  accountId: string;
};

/** Shape of the managed 11.3+ explicit-ownership include file. */
export type ExplicitOwnershipConfig = {
  agents: {
    ownership: "explicit";
    defaults: {
      heartbeat: {
        directPolicy: "block";
        target: "none";
        agentId: string;
      };
      systemAgent: {
        agentId: string;
      };
    };
  };
  bindings: Array<{
    agentId: string;
    comment?: string;
    match: { channel: string; accountId: string };
  }>;
};

// ── Constants ───────────────────────────────────────────────────────────────

// Regex copied from OpenClaw 2026.9.x src/config/zod-schema.agents.ts:35-39
const AGENT_ID_REGEX = /^[a-z0-9_][a-z0-9_-]{0,63}$/i;

// Regex copied from OpenClaw 2026.11.3 packages/normalization-core/src/agent-id.ts
const ACCOUNT_ID_VALID_RE = /^[a-z0-9][a-z0-9_-]{0,63}$/i;
const ACCOUNT_ID_INVALID_CHARS_RE = /[^a-z0-9_-]+/g;
const ACCOUNT_ID_LEADING_DASH_RE = /^-+/;
const ACCOUNT_ID_TRAILING_DASH_RE = /-+$/;

/**
 * Normalize a channel account id using the same rules as OpenClaw 2026.11.3
 * routing (src/routing/account-id.ts → normalizeAgentIdStrict).
 */
export function normalizeRoutingAccountId(value: string | undefined | null): string {
  const trimmed = (value ?? "").trim();
  const normalized = trimmed.toLowerCase();
  if (ACCOUNT_ID_VALID_RE.test(trimmed)) {
    return normalized;
  }
  return (
    normalized
      .replace(ACCOUNT_ID_INVALID_CHARS_RE, "-")
      .replace(ACCOUNT_ID_LEADING_DASH_RE, "")
      .replace(ACCOUNT_ID_TRAILING_DASH_RE, "")
      .slice(0, 64) || "default"
  );
}

/**
 * Optional variant: returns undefined when the normalized id would be empty.
 */
export function normalizeOptionalRoutingAccountId(
  value: string | undefined | null,
): string | undefined {
  const trimmed = (value ?? "").trim();
  const normalized = trimmed.toLowerCase();
  if (ACCOUNT_ID_VALID_RE.test(trimmed)) {
    return normalized;
  }
  const candidate = normalized
    .replace(ACCOUNT_ID_INVALID_CHARS_RE, "-")
    .replace(ACCOUNT_ID_LEADING_DASH_RE, "")
    .replace(ACCOUNT_ID_TRAILING_DASH_RE, "")
    .slice(0, 64);
  return candidate || undefined;
}

// #660 — The config schema (zod-schema.agent-runtime.ts) accepts 9 values;
// the DB CHECK only enforces 7. We validate against the schema contract
// (the consumer boundary), not the DB CHECK.
const VALID_THINKING_DEFAULTS = new Set([
  "off",
  "minimal",
  "low",
  "medium",
  "high",
  "xhigh",
  "adaptive",
  "max",
  "ultra",
]);

// TC-707-010: known provider prefixes are projected from the shared registry.
// We only ever store the keys; provider blocks containing secrets are never
// logged or returned.
const PROVIDER_REGISTRY_PATH = "/opt/agents/shared-config/models-providers.json";

function loadKnownProviders(): Set<string> {
  try {
    const raw = fs.readFileSync(PROVIDER_REGISTRY_PATH, "utf-8");
    const data = JSON.parse(raw) as Record<string, unknown>;
    return new Set(Object.keys(data));
  } catch {
    // Registry unreadable — skip warnings rather than failing.
    return new Set();
  }
}

const KNOWN_PROVIDERS = loadKnownProviders();

// TC-707 dedup: warn once per (agentId, providerPrefix) per process lifetime.
const warnedProviderPrefixes = new Set<string>();

/** Test-only: reset the once-per-process provider-prefix warning set. */
export function resetProviderPrefixWarnings(): void {
  warnedProviderPrefixes.clear();
}

/** Minimal logger surface used by buildAgentsList for warnings. */
export type BuildLogger = { warn: (msg: string) => void };

/** Logger surface used by sync helpers that also emit info messages. */
export type SyncLogger = { warn: (msg: string) => void; info: (msg: string) => void };

// ── SQL ─────────────────────────────────────────────────────────────────────

// Queries get_agent_export_rows(), which scopes results to the connecting role
// (session_user) and subagents owning that role via `parent_agents` array overlap.
// The function lives in nova-mind/database/schema.sql and is owned by newhart.
// It already filters to status='active' AND model IS NOT NULL; the generator
// re-applies those filters defensively so adversarial fixtures cannot bypass them.
const AGENTS_QUERY = `
  SELECT name, model, fallback_models, thinking, instance_type, is_default, allowed_subagents,
         heartbeat_enabled, heartbeat_every, heartbeat_target, heartbeat_to, heartbeat_isolated_session
  FROM get_agent_export_rows();
`;

// Pre-088 tolerance: peers may run agent-config-sync before migration 088 adds
// the heartbeat_isolated_session column. This fallback omits that column so the
// sync never crashes on a pre-migration DB.
const AGENTS_QUERY_WITHOUT_ISOLATED_SESSION = `
  SELECT name, model, fallback_models, thinking, instance_type, is_default, allowed_subagents,
         heartbeat_enabled, heartbeat_every, heartbeat_target, heartbeat_to
  FROM get_agent_export_rows();
`;

// Queries HEARTBEAT records for all agents that have agent-scoped entries.
const HEARTBEAT_QUERY = `
  SELECT agent_name, content
  FROM agent_bootstrap_context
  WHERE file_key = 'HEARTBEAT'
    AND agent_name IS NOT NULL
`;

// ── Helpers ─────────────────────────────────────────────────────────────────

/**
 * Normalize the DB `fallback_models` value into a string array.
 *
 * - `null` / `undefined` → `[]`
 * - array → shallow copy
 * - string → `[string]` and report via skipped
 * - any other type → `undefined` (caller should skip the row)
 */
function normalizeFallbackModels(
  value: unknown,
  agentName: string,
  skipped: Array<{ name: string; reason: string }>,
): string[] | undefined {
  if (value == null) {
    return [];
  }
  if (Array.isArray(value)) {
    return [...value as string[]];
  }
  if (typeof value === "string") {
    // Malformed scalar: report loudly but recover to a single-element array
    // so one bad row does not break the whole file.
    skipped.push({
      name: agentName,
      reason: "fallback_models was a scalar string; normalized to single-element array",
    });
    return [value];
  }
  skipped.push({
    name: agentName,
    reason: `fallback_models has unsupported type ${typeof value}`,
  });
  return undefined;
}

// ── Provider-prefix helpers ────────────────────────────────────────────────

/**
 * Extract the provider prefix from a model string (the part before the first
 * '/'). Returns `null` when the string contains no slash.
 */
function extractProviderPrefix(model: string): string | null {
  const idx = model.indexOf("/");
  if (idx === -1) return null;
  return model.slice(0, idx);
}

/**
 * TC-707-010: warn once per unrecognized provider prefix on a model string.
 * The model value itself is still emitted unchanged; this is only a warning.
 * When the registry is unreadable, KNOWN_PROVIDERS is empty and we skip
 * warnings entirely rather than failing.
 */
function warnIfUnknownProviderPrefix(
  id: string,
  model: string,
  log: BuildLogger,
): void {
  if (KNOWN_PROVIDERS.size === 0) return;
  const prefix = extractProviderPrefix(model);
  if (prefix == null) {
    const key = `${id}:<no-prefix>`;
    if (warnedProviderPrefixes.has(key)) return;
    warnedProviderPrefixes.add(key);
    log.warn(
      `agent_config_sync: agent '${id}' model '${model}' has no provider prefix`,
    );
  } else if (!KNOWN_PROVIDERS.has(prefix)) {
    const key = `${id}:${prefix}`;
    if (warnedProviderPrefixes.has(key)) return;
    warnedProviderPrefixes.add(key);
    log.warn(
      `agent_config_sync: agent '${id}' model '${model}' has unrecognized provider prefix '${prefix}'`,
    );
  }
}

/**
 * TC-707-010: check all model strings in an entry (primary + fallbacks) and
 * warn for unknown/missing provider prefixes.
 */
function warnIfUnknownProviderPrefixes(
  id: string,
  model: AgentEntryConfig["model"],
  log: BuildLogger,
): void {
  if (typeof model === "string") {
    warnIfUnknownProviderPrefix(id, model, log);
    return;
  }
  warnIfUnknownProviderPrefix(id, model.primary, log);
  for (const fallback of model.fallbacks) {
    warnIfUnknownProviderPrefix(id, fallback, log);
  }
}

// ── Build ───────────────────────────────────────────────────────────────────

/**
 * Build the agents entries as a keyed object from raw DB rows.
 *
 * - Peer agents are already excluded by the SQL query
 * - Only `status='active'` rows are included (TC-707-005)
 * - Rows with a missing/NULL model are skipped (TC-707-009)
 * - Rows with malformed `fallback_models` are skipped or normalized (TC-707-008)
 * - Rows with an invalid agent id are skipped (defensive)
 * - Under `ownershipMode: "legacy"` the default agent gets `default: true`
 *   (OpenClaw 2026.9.x). Under `ownershipMode: "explicit"` the marker is
 *   omitted and default ownership is expressed via `agents.ownership`,
 *   `agents.defaults.systemAgent`, and channel `bindings` (OpenClaw 2026.11.3+).
 * - Empty or NULL fallback_models → string model form (not object)
 * - DB `thinking` column mapped to `thinkingDefault` when it is a valid
 *   schema enum value; key omitted when null, empty, or unknown
 * - subagents.allowAgents included when allowed_subagents is non-empty, sorted
 * - Output keys sorted by agent name (id)
 * - Duplicate raw names are treated as a hard error BEFORE any entry is emitted
 * - Unknown/malformed provider prefixes are warned but still emitted (TC-707-010)
 */
export function buildAgentsList(
  rows: AgentRow[],
  options?: BuildAgentsListOptions,
): BuildAgentsListResult {
  const log = options?.logger ?? console;
  const ownershipMode = options?.ownershipMode ?? "explicit";
  const entries: Record<string, AgentEntryConfig> = {};
  const skipped: Array<{ name: string; reason: string }> = [];

  // Duplicate-name guard: two rows with the same literal name would silently
  // collapse in the keyed output. Detect this on raw input BEFORE building the
  // entries object and fail loudly, reporting both occurrences.
  const seenNames = new Map<string, number>();
  for (let i = 0; i < rows.length; i++) {
    const name = rows[i]?.name;
    if (typeof name !== "string") continue;
    if (seenNames.has(name)) {
      const firstIdx = seenNames.get(name)!;
      throw new Error(
        `Duplicate agent name '${name}' at rows ${firstIdx} and ${i}; ` +
          `each agent id must appear exactly once`,
      );
    }
    seenNames.set(name, i);
  }

  for (const row of rows) {
    const rowName = row.name ?? "(unnamed)";

    // TC-707-005: only active rows
    if (row.status != null && row.status !== "active") {
      skipped.push({ name: rowName, reason: `status='${row.status}' (not 'active')` });
      continue;
    }

    // Defensive: every emitted entry key must satisfy the 2026.9.x agent-id regex
    if (typeof row.name !== "string" || !AGENT_ID_REGEX.test(row.name)) {
      skipped.push({ name: rowName, reason: "invalid or missing agent id" });
      continue;
    }

    // TC-707-009: NULL model on an active row must never emit "model": null
    if (row.model == null) {
      skipped.push({ name: row.name, reason: "model is null or missing" });
      continue;
    }

    // TC-707-008: fallback_models must be an array (or a single string we can normalize)
    const fallbackModels = normalizeFallbackModels(row.fallback_models, row.name, skipped);
    if (fallbackModels === undefined) {
      // Row was skipped due to an unrecoverable wrong-type fallback_models.
      continue;
    }

    const hasFallbacks = fallbackModels.length > 0;

    // Build entry value (no `id` — the object key IS the id).
    const entry: AgentEntryConfig = {
      model: hasFallbacks
        ? { primary: row.model, fallbacks: fallbackModels }
        : row.model,
    };

    // Legacy OpenClaw 2026.9.x default marker. Only emit under legacy mode;
    // 11.3+ with agents.ownership=explicit rejects this marker.
    if (ownershipMode === "legacy" && row.is_default === true) {
      entry.default = true;
    }

    // #660 — Map DB `thinking` → `thinkingDefault` when it is a valid schema enum value.
    // Null, empty, unknown, wrong-type, mixed-case, or whitespace-padded values are omitted.
    if (
      typeof row.thinking === "string" &&
      row.thinking.length > 0 &&
      VALID_THINKING_DEFAULTS.has(row.thinking)
    ) {
      entry.thinkingDefault = row.thinking;
    }

    // Include subagents.allowAgents if set (sorted for stable output)
    if (Array.isArray(row.allowed_subagents) && row.allowed_subagents.length > 0) {
      entry.subagents = { allowAgents: [...row.allowed_subagents].sort() };
    }

    // #262/#273/#714 — Per-agent heartbeat config
    // OpenClaw schema requires heartbeat to be an object, not a boolean.
    // heartbeat_enabled = true  → emit heartbeat object with non-NULL sub-fields only
    // heartbeat_enabled = false | NULL → omit key (inherits agents.defaults.heartbeat)
    if (row.heartbeat_enabled === true) {
      const hb: HeartbeatConfig = {};
      if (row.heartbeat_every != null) hb.every = row.heartbeat_every;
      if (row.heartbeat_target != null) hb.target = row.heartbeat_target;
      if (row.heartbeat_to != null) hb.to = row.heartbeat_to;
      // #714 — isolatedSession must be explicit when the row has a value.
      // true → true, false → false, null/undefined → omitted.
      if (row.heartbeat_isolated_session === true) {
        hb.isolatedSession = true;
      } else if (row.heartbeat_isolated_session === false) {
        hb.isolatedSession = false;
      }
      entry.heartbeat = hb;
    }

    // TC-707-010: unknown/malformed provider prefixes are allowed by the host
    // schema, but we warn once per occurrence so operators can spot typos.
    warnIfUnknownProviderPrefixes(row.name, entry.model, log);

    entries[row.name] = entry;
  }

  // Sort keys by agent name (id) for stable, deterministic output
  const sortedEntries: Record<string, AgentEntryConfig> = {};
  for (const key of Object.keys(entries).sort((a, b) => a.localeCompare(b))) {
    sortedEntries[key] = entries[key];
  }

  return { entries: sortedEntries, skipped };
}

// ── Validation ──────────────────────────────────────────────────────────────

/**
 * Validate that a candidate `agents.entries` object satisfies the 2026.9.x
 * schema subset actually emitted by this generator. Throws a descriptive error
 * if the object would fail `openclaw config validate`.
 *
 * This is called BEFORE the atomic rename in writeAgentsJsonAtomically() so a
 * bad generated file can never be promoted where hot reload could pick it up
 * (TC-707-004).
 */
export function validateAgentsEntries(
  entries: Record<string, AgentEntryConfig>,
): void {
  if (!entries || typeof entries !== "object" || Array.isArray(entries)) {
    throw new Error("agents.entries must be an object");
  }

  const keys = Object.keys(entries);
  if (keys.length === 0) {
    throw new Error("agents.entries must contain at least one configured agent");
  }

  const normalizedIds = new Map<string, string>();
  let defaultCount = 0;

  for (const id of keys) {
    if (!AGENT_ID_REGEX.test(id)) {
      throw new Error(`agents.entries key "${id}" is not a valid agent id`);
    }

    const entry = entries[id];
    if (!entry || typeof entry !== "object" || Array.isArray(entry)) {
      throw new Error(`agents.entries["${id}"] must be an object`);
    }

    if (Object.hasOwn(entry, "id")) {
      throw new Error(
        `agents.entries["${id}"] must not contain an "id" field (the key is the id)`,
      );
    }

    if (!Object.hasOwn(entry, "model")) {
      throw new Error(`agents.entries["${id}"] is missing required "model"`);
    }

    if (typeof entry.model === "string") {
      // TC-707-010: unknown provider prefixes are allowed by AgentModelSchema,
      // so we only enforce the type here.
      if (entry.model.length === 0) {
        throw new Error(`agents.entries["${id}"].model must not be empty`);
      }
    } else if (typeof entry.model === "object" && entry.model !== null) {
      if (typeof entry.model.primary !== "string" || entry.model.primary.length === 0) {
        throw new Error(
          `agents.entries["${id}"].model.primary must be a non-empty string`,
        );
      }
      if (
        entry.model.fallbacks !== undefined &&
        !Array.isArray(entry.model.fallbacks)
      ) {
        throw new Error(
          `agents.entries["${id}"].model.fallbacks must be an array`,
        );
      }
    } else {
      throw new Error(
        `agents.entries["${id}"].model must be a string or an object with primary/fallbacks`,
      );
    }

    if (
      Object.hasOwn(entry, "thinkingDefault") &&
      (typeof entry.thinkingDefault !== "string" ||
        !VALID_THINKING_DEFAULTS.has(entry.thinkingDefault))
    ) {
      throw new Error(
        `agents.entries["${id}"].thinkingDefault is not a valid thinking tier`,
      );
    }

    if (Object.hasOwn(entry, "subagents")) {
      if (
        !entry.subagents ||
        typeof entry.subagents !== "object" ||
        Array.isArray(entry.subagents) ||
        !Array.isArray(entry.subagents.allowAgents)
      ) {
        throw new Error(
          `agents.entries["${id}"].subagents must be an object with allowAgents array`,
        );
      }
    }

    if (Object.hasOwn(entry, "heartbeat")) {
      if (
        !entry.heartbeat ||
        typeof entry.heartbeat !== "object" ||
        Array.isArray(entry.heartbeat)
      ) {
        throw new Error(
          `agents.entries["${id}"].heartbeat must be an object`,
        );
      }
    }

    if (entry.default === true) {
      defaultCount++;
    } else if (entry.default !== undefined && entry.default !== true) {
      throw new Error(
        `agents.entries["${id}"].default must be true or undefined`,
      );
    }

    const normalized = id.toLowerCase();
    const firstKey = normalizedIds.get(normalized);
    if (firstKey) {
      throw new Error(
        `agents.entries keys "${firstKey}" and "${id}" resolve to the same normalized id`,
      );
    }
    normalizedIds.set(normalized, id);
  }

  if (defaultCount > 1) {
    throw new Error(
      `agents.entries must contain at most one default=true entry (found ${defaultCount})`,
    );
  }
}

// ── Explicit ownership config (OpenClaw 2026.11.3+) ─────────────────────────

/** Known channel config keys that are not channel IDs. */
const CHANNELS_META_KEYS = new Set(["defaults", "modelByChannel"]);

/**
 * Enumerate configured channel accounts from the resolved OpenClaw config.
 *
 * - Looks at `channels.<channelId>`.
 * - Skips internal keys (`defaults`, `modelByChannel`).
 * - Skips channels whose `enabled` flag is explicitly `false`.
 * - If a channel has `accounts: { <accountId>: {...}, ... }`, emits one entry
 *   per account that is not explicitly disabled.
 * - If a channel has no `accounts`, emits a single `accountId: "default"` entry.
 */
export function detectConfiguredChannelAccounts(
  config: Record<string, unknown>,
): ChannelAccount[] {
  const channels = config.channels as Record<string, unknown> | undefined;
  if (!channels || typeof channels !== "object" || Array.isArray(channels)) {
    return [];
  }

  const accounts: ChannelAccount[] = [];
  for (const [channelId, channelValue] of Object.entries(channels)) {
    if (CHANNELS_META_KEYS.has(channelId)) continue;
    if (!channelValue || typeof channelValue !== "object" || Array.isArray(channelValue)) {
      continue;
    }
    const channel = channelValue as Record<string, unknown>;
    if (channel.enabled === false) continue;

    const accountEntries = channel.accounts as Record<string, unknown> | undefined;
    if (accountEntries && typeof accountEntries === "object" && !Array.isArray(accountEntries)) {
      for (const [accountId, accountValue] of Object.entries(accountEntries)) {
        if (
          accountValue &&
          typeof accountValue === "object" &&
          !Array.isArray(accountValue) &&
          (accountValue as Record<string, unknown>).enabled === false
        ) {
          continue;
        }
        accounts.push({ channel: channelId, accountId: normalizeRoutingAccountId(accountId) });
      }
    } else {
      accounts.push({ channel: channelId, accountId: "default" });
    }
  }

  // Stable ordering for idempotent serialization.
  accounts.sort((a, b) => {
    const byChannel = a.channel.localeCompare(b.channel);
    return byChannel !== 0 ? byChannel : a.accountId.localeCompare(b.accountId);
  });
  return accounts;
}

/**
 * Build the managed explicit-ownership include config for OpenClaw 2026.11.3+.
 *
 * The returned object is meant to be merged at the root of openclaw.json via
 * a `"$include": "./agents-explicit.json"` directive. It contributes:
 *   - `agents.ownership = "explicit"`
 *   - `agents.defaults.heartbeat.agentId` / `directPolicy` / `target`
 *   - `agents.defaults.systemAgent.agentId`
 *   - top-level `bindings[]` routing every configured channel account to the
 *     default peer agent.
 */
function explicitBindingMatchKey(channel: string, accountId: string): string {
  return `${channel}:${normalizeRoutingAccountId(accountId)}`;
}

export function buildExplicitOwnershipConfig(
  peerAgentName: string,
  channelAccounts: ChannelAccount[],
  existingSiblingBindings?: Array<{ match: { channel: string; accountId: string } }>,
): ExplicitOwnershipConfig {
  // Sort for stable, deterministic output regardless of input order.
  const sortedAccounts = [...channelAccounts].sort((a, b) => {
    const byChannel = a.channel.localeCompare(b.channel);
    return byChannel !== 0 ? byChannel : a.accountId.localeCompare(b.accountId);
  });

  const covered = new Set(
    (existingSiblingBindings ?? []).map((b) =>
      explicitBindingMatchKey(b.match.channel, b.match.accountId),
    ),
  );

  const bindings: ExplicitOwnershipConfig["bindings"] = [];
  const seen = new Set<string>();
  for (const { channel, accountId } of sortedAccounts) {
    const key = explicitBindingMatchKey(channel, accountId);
    if (covered.has(key) || seen.has(key)) {
      continue;
    }
    seen.add(key);
    bindings.push({
      agentId: peerAgentName,
      comment: `${channel} ${accountId} account -> ${peerAgentName} (replaces legacy default:true; nova-mind#819)`,
      match: { channel, accountId },
    });
  }

  return {
    agents: {
      ownership: "explicit",
      defaults: {
        heartbeat: {
          directPolicy: "block",
          target: "none",
          agentId: peerAgentName,
        },
        systemAgent: {
          agentId: peerAgentName,
        },
      },
    },
    bindings,
  };
}

/**
 * Validate that a candidate explicit-ownership config satisfies the 2026.11.3
 * schema subset emitted by this generator.
 */
export function validateExplicitOwnershipConfig(
  config: ExplicitOwnershipConfig,
): void {
  if (!config || typeof config !== "object" || Array.isArray(config)) {
    throw new Error("explicit ownership config must be an object");
  }
  if (config.agents?.ownership !== "explicit") {
    throw new Error("explicit ownership config must set agents.ownership to 'explicit'");
  }
  if (typeof config.agents?.defaults?.heartbeat?.agentId !== "string" ||
      config.agents.defaults.heartbeat.agentId.length === 0) {
    throw new Error("explicit ownership config must set agents.defaults.heartbeat.agentId");
  }
  if (config.agents.defaults.heartbeat.directPolicy !== "block") {
    throw new Error("explicit ownership config must set agents.defaults.heartbeat.directPolicy to 'block'");
  }
  if (config.agents.defaults.heartbeat.target !== "none") {
    throw new Error("explicit ownership config must set agents.defaults.heartbeat.target to 'none'");
  }
  if (typeof config.agents?.defaults?.systemAgent?.agentId !== "string" ||
      config.agents.defaults.systemAgent.agentId.length === 0) {
    throw new Error("explicit ownership config must set agents.defaults.systemAgent.agentId");
  }
  if (!Array.isArray(config.bindings)) {
    throw new Error("explicit ownership config must set bindings to an array");
  }
  const seenMatches = new Set<string>();
  for (const binding of config.bindings) {
    if (!binding || typeof binding !== "object" || Array.isArray(binding)) {
      throw new Error("explicit ownership binding must be an object");
    }
    if (typeof binding.agentId !== "string" || binding.agentId.length === 0) {
      throw new Error("explicit ownership binding must set agentId");
    }
    if (!binding.match || typeof binding.match !== "object" || Array.isArray(binding.match)) {
      throw new Error("explicit ownership binding must set match object");
    }
    if (typeof binding.match.channel !== "string" || binding.match.channel.length === 0) {
      throw new Error("explicit ownership binding must set match.channel");
    }
    if (typeof binding.match.accountId !== "string" || binding.match.accountId.length === 0) {
      throw new Error("explicit ownership binding must set match.accountId");
    }
    const matchKey = explicitBindingMatchKey(binding.match.channel, binding.match.accountId);
    if (seenMatches.has(matchKey)) {
      throw new Error(
        `explicit ownership config has duplicate binding for ${binding.match.channel}:${binding.match.accountId}`,
      );
    }
    seenMatches.add(matchKey);
  }
}

// ── Query ───────────────────────────────────────────────────────────────────

/**
 * Fetch agent rows from the database.
 *
 * Pre-088 tolerance: detects whether the `heartbeat_isolated_session` column
 * exists and falls back to a query without it when it does not. This lets peers
 * with their own <agent>_memory DB run agent-config-sync before migration 088
 * without crashing.
 */
export async function fetchAgentRows(client: pg.Client): Promise<AgentRow[]> {
  const colCheck = await client.query<{ exists: boolean }>(`
    SELECT EXISTS (
      SELECT 1 FROM information_schema.columns
      WHERE table_schema = 'public'
        AND table_name = 'agents'
        AND column_name = 'heartbeat_isolated_session'
    ) AS exists
  `);
  const hasIsolatedSessionCol = colCheck.rows[0]?.exists === true;
  const query = hasIsolatedSessionCol
    ? AGENTS_QUERY
    : AGENTS_QUERY_WITHOUT_ISOLATED_SESSION;
  const result = await client.query<AgentRow>(query);
  return result.rows;
}

/**
 * Fetch HEARTBEAT records for all agents from agent_bootstrap_context.
 */
export async function fetchHeartbeatRecords(
  client: pg.Client,
): Promise<HeartbeatRow[]> {
  const result = await client.query<HeartbeatRow>(HEARTBEAT_QUERY);
  return result.rows;
}

// ── Write helpers ───────────────────────────────────────────────────────────

/**
 * Read a JSON file if it exists and is valid JSON. Returns `undefined` if the
 * file is missing or cannot be parsed.
 */
async function readJsonFile<T>(filePath: string): Promise<T | undefined> {
  try {
    const raw = await fs.promises.readFile(filePath, "utf-8");
    return JSON.parse(raw) as T;
  } catch {
    return undefined;
  }
}

/**
 * Write a JSON file atomically (tmp + rename) with 0600 permissions.
 * Validates the data with the provided validator before writing.
 */
async function writeJsonAtomically<T>(
  filePath: string,
  data: T,
  validator: (data: T) => void,
): Promise<void> {
  validator(data);

  const dir = path.dirname(filePath);
  await fs.promises.mkdir(dir, { recursive: true });

  const tmpFile = path.join(
    dir,
    `${path.basename(filePath)}.${crypto.randomUUID()}.tmp`,
  );

  const content = JSON.stringify(data, null, 2) + "\n";

  await fs.promises.writeFile(tmpFile, content, { encoding: "utf-8", mode: 0o600 });
  await fs.promises.rename(tmpFile, filePath);
}

// ── openclaw.json root-include helper ───────────────────────────────────────

/**
 * Idempotently ensure that `openclaw.json` contains a root-level `$include`
 * directive for the managed explicit-ownership file.
 *
 * - If the include is already present (string or array), the file is left
 *   untouched and `false` is returned.
 * - If absent, it is added. A single existing string include is converted to
 *   an array; otherwise the directive is added as a string.
 * - Only the root file is modified; the plugin never edits $include-owned
 *   children (it writes them directly instead).
 *
 * Returns `true` if openclaw.json was changed.
 */
export function ensureRootInclude(
  openclawConfig: Record<string, unknown>,
  includePath: string,
): { changed: boolean; config: Record<string, unknown> } {
  const INCLUDE_KEY = "$include";
  const existing = openclawConfig[INCLUDE_KEY];

  if (typeof existing === "string") {
    if (existing === includePath) {
      return { changed: false, config: openclawConfig };
    }
    return {
      changed: true,
      config: {
        ...openclawConfig,
        [INCLUDE_KEY]: [existing, includePath],
      },
    };
  }

  if (Array.isArray(existing)) {
    if (existing.includes(includePath)) {
      return { changed: false, config: openclawConfig };
    }
    return {
      changed: true,
      config: {
        ...openclawConfig,
        [INCLUDE_KEY]: [...existing, includePath],
      },
    };
  }

  return {
    changed: true,
    config: {
      ...openclawConfig,
      [INCLUDE_KEY]: includePath,
    },
  };
}

const INCLUDE_KEY = "$include";

function rootIncludes(
  openclawConfig: Record<string, unknown>,
  includePath: string,
): boolean {
  const existing = openclawConfig[INCLUDE_KEY];
  if (typeof existing === "string") {
    return existing === includePath;
  }
  if (Array.isArray(existing)) {
    return existing.some((item) => item === includePath);
  }
  return false;
}

function hasHandAuthoredExplicitOwnershipKeys(
  openclawConfig: Record<string, unknown>,
): boolean {
  const agents = openclawConfig.agents as Record<string, unknown> | undefined;
  if (agents && typeof agents === "object" && !Array.isArray(agents)) {
    if (agents.ownership !== undefined) return true;
    const defaults = agents.defaults as Record<string, unknown> | undefined;
    if (defaults && typeof defaults === "object" && !Array.isArray(defaults)) {
      if (defaults.heartbeat !== undefined) return true;
      if (defaults.systemAgent !== undefined) return true;
    }
  }
  if (Array.isArray(openclawConfig.bindings)) {
    return true;
  }
  return false;
}

const explicitOwnershipInstructionLogged = new Set<string>();

function logExplicitOwnershipInstruction(
  openclawConfigPath: string,
  log: SyncLogger,
  message: string,
): void {
  if (explicitOwnershipInstructionLogged.has(openclawConfigPath)) {
    return;
  }
  explicitOwnershipInstructionLogged.add(openclawConfigPath);
  log.info(`agent_config_sync: ${message}`);
}

/** Test-only: reset the once-per-process explicit-ownership instruction set. */
export function resetExplicitOwnershipInstructions(): void {
  explicitOwnershipInstructionLogged.clear();
}

// ── Agents JSON write ───────────────────────────────────────────────────────

/**
 * Write agents.json atomically (write to temp with 0600, validate, then rename).
 * Accepts a keyed object of agent entries. Validation happens BEFORE the rename
 * so an invalid file is never promoted to the live path (TC-707-004).
 */
export async function writeAgentsJsonAtomically(
  filePath: string,
  data: Record<string, AgentEntryConfig>,
): Promise<void> {
  // TC-707-004: validate BEFORE any file is written where a watcher could see it.
  validateAgentsEntries(data);

  const dir = path.dirname(filePath);
  await fs.promises.mkdir(dir, { recursive: true });

  const tmpFile = path.join(
    dir,
    `${path.basename(filePath)}.${crypto.randomUUID()}.tmp`,
  );

  const content = JSON.stringify(data, null, 2) + "\n";

  await fs.promises.writeFile(tmpFile, content, { encoding: "utf-8", mode: 0o600 });
  await fs.promises.rename(tmpFile, filePath);
}

// ── Heartbeat sync ─────────────────────────────────────────────────────────

/**
 * Sync HEARTBEAT.md files for all agents from agent_bootstrap_context.
 *
 * Workspace routing:
 *   - defaultAgentName → <stateDir>/workspace/HEARTBEAT.md
 *   - all others       → <stateDir>/workspace-<agent_name>/HEARTBEAT.md
 *
 * Uses atomic writes (tmp + rename). Skips write when content is unchanged.
 * Creates workspace directory if it does not exist.
 *
 * Returns a list of agent names whose HEARTBEAT.md files were updated.
 */
export async function syncHeartbeatFiles(
  client: pg.Client,
  stateDir: string,
  defaultAgentName: string,
): Promise<string[]> {
  const rows = await fetchHeartbeatRecords(client);
  const updated: string[] = [];

  for (const row of rows) {
    const wsDir =
      row.agent_name === defaultAgentName
        ? path.join(stateDir, "workspace")
        : path.join(stateDir, `workspace-${row.agent_name}`);

    const filePath = path.join(wsDir, "HEARTBEAT.md");
    const newContent = row.content;

    // Skip write if content is NULL — preserve existing file
    if (newContent == null) continue;

    // Skip write if content unchanged
    try {
      const existing = await fs.promises.readFile(filePath, "utf-8");
      if (existing === newContent) continue;
    } catch {
      // File doesn't exist yet — continue to write
    }

    // Create workspace directory if needed
    await fs.promises.mkdir(wsDir, { recursive: true });

    // Atomic write: tmp file + rename
    const tmpFile = path.join(
      wsDir,
      `HEARTBEAT.md.${crypto.randomUUID()}.tmp`,
    );
    await fs.promises.writeFile(tmpFile, newContent, { encoding: "utf-8" });
    await fs.promises.rename(tmpFile, filePath);

    updated.push(row.agent_name);
  }

  return updated;
}

// ── Full sync ───────────────────────────────────────────────────────────────

/**
 * Perform a full sync: query DB → build keyed entries → validate → atomic write.
 * Returns true if the file was changed, false if identical.
 */
export async function syncAgentsConfig(
  client: pg.Client,
  outputPath: string,
  options?: BuildAgentsListOptions,
): Promise<boolean> {
  const rows = await fetchAgentRows(client);
  const { entries } = buildAgentsList(rows, options);
  const newContent = JSON.stringify(entries, null, 2) + "\n";

  // Check if file already matches (avoid unnecessary writes / watcher triggers)
  try {
    const existing = await fs.promises.readFile(outputPath, "utf-8");
    if (existing === newContent) {
      return false;
    }
  } catch {
    // File doesn't exist yet — continue to write
  }

  await writeAgentsJsonAtomically(outputPath, entries);
  return true;
}

/**
 * Sync the managed explicit-ownership include file.
 *
 * OpenClaw 2026.11.3's config file watcher reloads the runtime automatically
 * when the include file changes, so this plugin never modifies openclaw.json
 * itself. The operator must add the root `"$include": "./agents-explicit.json"`
 * directive. Until then, we log a one-time instruction and stay out of the
 * way. We also refuse to manage the file when openclaw.json already contains
 * hand-authored explicit-ownership keys (agents.ownership,
 * agents.defaults.heartbeat, agents.defaults.systemAgent, or bindings), so we
 * never fight hand-written config.
 *
 * Returns `{ explicitChanged, openclawChanged }` indicating which files were
 * actually written. openclawChanged is always false in this implementation.
 * If both are false, the second restart is a no-op (idempotence).
 */
export async function syncExplicitOwnershipConfig(
  client: pg.Client,
  openclawConfigPath: string,
  explicitConfigPath: string,
  resolvedConfig: Record<string, unknown>,
  logger?: SyncLogger,
): Promise<{ explicitChanged: boolean; openclawChanged: boolean }> {
  const log = logger ?? console;
  const includePath = `./${path.basename(explicitConfigPath)}`;
  const openclawConfig = await readJsonFile<Record<string, unknown>>(openclawConfigPath) ?? {};

  const alreadyIncluded = rootIncludes(openclawConfig, includePath);
  const handAuthored = hasHandAuthoredExplicitOwnershipKeys(openclawConfig);

  if (!alreadyIncluded) {
    if (handAuthored) {
      logExplicitOwnershipInstruction(
        openclawConfigPath,
        log,
        `openclaw.json has hand-authored explicit-ownership keys (agents.ownership, ` +
          `agents.defaults.heartbeat, agents.defaults.systemAgent, and/or bindings). ` +
          `Managed explicit ownership is disabled. To enable it, move those keys into ` +
          `${path.basename(explicitConfigPath)} and add "\\"$include\\"": "${includePath}" ` +
          `to ${openclawConfigPath}.`,
      );
    } else {
      logExplicitOwnershipInstruction(
        openclawConfigPath,
        log,
        `Managed explicit ownership file is not included. Add "\\"$include\\"": "${includePath}" ` +
          `to ${openclawConfigPath} to enable managed explicit ownership bindings. ` +
          `A channel added by config edit gets its binding only on the next sync ` +
          `(gateway start or agent_config_changed NOTIFY).`,
      );
    }
    return { explicitChanged: false, openclawChanged: false };
  }

  // The operator added the $include themselves. We manage the include file but
  // never edit openclaw.json. Generated bindings skip any match already covered
  // by hand-authored sibling bindings so routing never has duplicate first-match
  // entries.

  const rows = await fetchAgentRows(client);
  const defaultAgentName =
    rows.find((r) => r.is_default === true)?.name ?? "nova";

  const channelAccounts = detectConfiguredChannelAccounts(resolvedConfig);
  const explicitConfig = buildExplicitOwnershipConfig(
    defaultAgentName,
    channelAccounts,
    Array.isArray(openclawConfig.bindings) ? openclawConfig.bindings : undefined,
  );

  let explicitChanged = false;
  const newExplicitContent = JSON.stringify(explicitConfig, null, 2) + "\n";
  try {
    const existing = await fs.promises.readFile(explicitConfigPath, "utf-8");
    if (existing !== newExplicitContent) {
      await writeJsonAtomically(explicitConfigPath, explicitConfig, validateExplicitOwnershipConfig);
      explicitChanged = true;
    }
  } catch {
    await writeJsonAtomically(explicitConfigPath, explicitConfig, validateExplicitOwnershipConfig);
    explicitChanged = true;
  }

  return { explicitChanged, openclawChanged: false };
}
