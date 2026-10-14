import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import { mkdtempSync, writeFileSync, rmSync, mkdirSync } from "fs";
import { tmpdir } from "os";
import { join } from "path";

/**
 * Plugin-harness tests for nova-mind#726: memory-extract as an OpenClaw
 * plugin.
 *
 * These tests exercise register(api), the message_received event adapter,
 * and the gateway_start/gateway_stop lifecycle hooks.
 */

vi.mock("child_process", () => ({
  spawn: vi.fn(),
  execFile: vi.fn(),
}));

import { spawn, execFile } from "child_process";
import register, {
  buildLegacyEvent,
  resetForTests,
  type PluginLogger,
} from "../src/index.ts";

interface FakeApi {
  logger: PluginLogger;
  pluginConfig: Record<string, unknown>;
  handlers: Record<string, any>;
  on: (hook: string, handler: any) => void;
}

function makeHomeDir(): string {
  return mkdtempSync(join(tmpdir(), "memory-extract-plugin-"));
}

function makePostgresConfig(homeDir: string, database: string): void {
  const dir = join(homeDir, ".openclaw");
  mkdirSync(dir, { recursive: true });
  writeFileSync(join(dir, "postgres.json"), JSON.stringify({ database }));
}

function cleanupHomeDir(homeDir: string): void {
  try {
    rmSync(homeDir, { recursive: true, force: true });
  } catch {}
}

function makeMockLogger(): PluginLogger {
  return {
    debug: vi.fn(),
    info: vi.fn(),
    warn: vi.fn(),
    error: vi.fn(),
  };
}

function makeSuccessfulChild(): any {
  return {
    stdin: { write: vi.fn(), end: vi.fn() },
    stdout: { on: vi.fn() },
    stderr: { on: vi.fn() },
    kill: vi.fn(),
    killed: false,
    on: vi.fn((event: string, handler: any) => {
      if (event === "close") handler(0, null);
    }),
  };
}

function mockPsql(): void {
  vi.mocked(execFile).mockImplementation((_cmd: any, args: any, cb: any) => {
    if (!Array.isArray(args)) {
      cb(null, "", "");
      return {} as any;
    }
    const sqlArg = args.find((a: any) => typeof a === "string" && a.includes("INSERT INTO"));
    if (sqlArg && sqlArg.includes("INSERT INTO channel_sessions")) {
      cb(null, "42\n", "");
    } else if (sqlArg && sqlArg.includes("INSERT INTO channel_transcripts")) {
      cb(null, "99\n", "");
    } else {
      cb(null, "", "");
    }
    return {} as any;
  });
}

function capturedPsqlSql(): string[] {
  return vi.mocked(execFile).mock.calls
    .filter((c) => c[0] === "psql")
    .map((c) => {
      const args = c[1] as string[];
      const sql = args.find((a) => typeof a === "string" && a.includes("INSERT INTO"));
      return sql || "";
    });
}

function makeFakeApi(pluginConfig: Record<string, unknown> = {}): FakeApi {
  const logger = makeMockLogger();
  const handlers: Record<string, any> = {};
  return {
    logger,
    pluginConfig,
    handlers,
    on(hook: string, handler: any) {
      handlers[hook] = handler;
    },
  };
}

describe("memory-extract plugin registration (#726)", () => {
  let originalHome: string | undefined;
  let homeDir: string;

  beforeEach(() => {
    originalHome = process.env.HOME;
    homeDir = makeHomeDir();
    process.env.HOME = homeDir;
    delete process.env.PGDATABASE;
    vi.mocked(spawn).mockReset();
    vi.mocked(execFile).mockReset();
    resetForTests();
  });

  afterEach(() => {
    if (originalHome === undefined) delete process.env.HOME;
    else process.env.HOME = originalHome;
    cleanupHomeDir(homeDir);
  });

  it("register captures api.logger and emits startup line", () => {
    makePostgresConfig(homeDir, "nova_memory");
    const api = makeFakeApi();

    register(api);

    expect(api.handlers.message_received).toBeDefined();
    expect(api.handlers.gateway_start).toBeDefined();
    expect(api.handlers.gateway_stop).toBeDefined();
    expect(
      (api.logger.info as ReturnType<typeof vi.fn>).mock.calls.some(
        (c: any) => (c[0] as string).includes("[memory-extract] startup")
      )
    ).toBe(true);
  });

  it("register surfaces db_unresolved via captured logger when DB is missing", () => {
    const api = makeFakeApi();

    register(api);

    expect(
      (api.logger.error as ReturnType<typeof vi.fn>).mock.calls.some(
        (c: any) =>
          (c[0] as string).includes("[memory-extract] startup failed") &&
          (c[0] as string).includes("reason=db_unresolved")
      )
    ).toBe(true);
  });

  it("gateway_start and gateway_stop both route through the captured logger", async () => {
    makePostgresConfig(homeDir, "nova_memory");
    const api = makeFakeApi();
    register(api);

    vi.mocked(spawn).mockImplementation(() => makeSuccessfulChild() as any);
    mockPsql();

    await api.handlers.message_received(
      {
        content: "This is a reasonably long test message for plugin extraction.",
        metadata: {},
      },
      { sessionKey: "agent:nova:discord:channel:123" }
    );

    // gateway_start is idempotent with register's startup.
    await api.handlers.gateway_start({ port: 8080 });

    (api.logger.info as ReturnType<typeof vi.fn>).mockClear();
    await api.handlers.gateway_stop({ reason: "test" });

    const shutdownMsg = (api.logger.info as ReturnType<typeof vi.fn>).mock.calls.find(
      (c: any) => (c[0] as string).includes("[memory-extract] shutdown")
    )?.[0] as string;
    expect(shutdownMsg).toBeDefined();
    expect(shutdownMsg).toContain("received=1");
    expect(shutdownMsg).toContain("stored=1");
  });

  it("message_received maps every sender field from host event/context", async () => {
    makePostgresConfig(homeDir, "nova_memory");
    const api = makeFakeApi();
    register(api);
    vi.mocked(spawn).mockImplementation(() => makeSuccessfulChild() as any);
    mockPsql();

    await api.handlers.message_received(
      {
        from: "Druidian",
        content: "Plugin-shaped message body for mapping test.",
        threadId: "thread-plugin-1",
        messageId: "msg-726",
        senderId: "330189773371080716",
        metadata: {
          senderUsername: "druidian",
          senderTag: "tag_123",
          isGroup: true,
          provider: "discord",
          channelName: "#software-engineering",
          guildId: "1492385947927445524",
        },
      },
      {
        channelId: "discord",
        accountId: "default",
        conversationId: "channel:1504704418551959685",
        sessionKey: "agent:nova:discord:channel:1504704418551959685",
        senderId: "330189773371080716",
      }
    );

    const sessionSql = capturedPsqlSql().find((s) =>
      s.includes("INSERT INTO channel_sessions")
    );
    expect(sessionSql).toBeDefined();
    expect(sessionSql).toContain("discord");
    expect(sessionSql).toContain("channel:1504704418551959685");
    expect(sessionSql).toContain("'thread-plugin-1'");
    expect(sessionSql).toContain("group");
    expect(sessionSql).toContain("#software-engineering");
    expect(sessionSql).toContain("1492385947927445524");

    const txSql = capturedPsqlSql().find((s) =>
      s.includes("INSERT INTO channel_transcripts")
    );
    expect(txSql).toBeDefined();
    expect(txSql).toContain("330189773371080716");
    expect(txSql).toContain("Druidian");
    expect(txSql).toContain("druidian");
    expect(txSql).toContain("tag_123");
  });

  it("buildLegacyEvent covers all #708/#726 sender fields", () => {
    const legacy = buildLegacyEvent(
      {
        from: "SenderName",
        content: "hello world",
        threadId: 42,
        messageId: "msg-1",
        senderId: "sender-1",
        metadata: {
          senderName: "OverrideName",
          senderId: "meta-sender-1",
          isGroup: true,
          senderUsername: "user1",
          senderTag: "tag1",
          provider: "telegram",
          channelName: "#chan",
          guildId: "guild-1",
        },
      },
      {
        channelId: "fallback-provider",
        conversationId: "conv-1",
        sessionKey: "agent:nova:telegram:chat:1",
        senderId: "ctx-sender-1",
      }
    );

    expect(legacy.type).toBe("message");
    expect(legacy.action).toBe("received");
    expect(legacy.sessionKey).toBe("agent:nova:telegram:chat:1");
    expect(legacy.threadId).toBe(42);
    expect(legacy.context.content).toBe("hello world");

    const meta = legacy.context.metadata;
    expect(meta.senderName).toBe("OverrideName"); // metadata wins over event.from
    expect(meta.senderId).toBe("meta-sender-1"); // metadata wins over ctx.senderId
    expect(meta.isGroup).toBe(true);
    expect(meta.senderUsername).toBe("user1");
    expect(meta.senderTag).toBe("tag1");
    expect(meta.provider).toBe("telegram"); // metadata wins over ctx.channelId
    expect(meta.channelName).toBe("#chan");
    expect(meta.guildId).toBe("guild-1");
    expect(meta.conversationId).toBe("conv-1");
    expect(meta.messageId).toBe("msg-1");
  });

  it("buildLegacyEvent uses host fallbacks when metadata is absent", () => {
    const legacy = buildLegacyEvent(
      {
        from: "FallbackName",
        content: "hello",
        senderId: "event-sender",
      },
      {
        channelId: "signal",
        sessionKey: "agent:nova:signal:group:abc",
        senderId: "ctx-sender",
      }
    );

    expect(legacy.context.metadata.senderName).toBe("FallbackName");
    expect(legacy.context.metadata.senderId).toBe("ctx-sender"); // ctx beats event
    expect(legacy.context.metadata.provider).toBe("signal");
    expect(legacy.context.metadata.isGroup).toBe(false);
    expect(legacy.sessionKey).toBe("agent:nova:signal:group:abc");
  });
});
