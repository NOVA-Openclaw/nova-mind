import { z } from "zod";
import type { ChannelConfigSchema } from "openclaw/plugin-sdk";

/**
 * Zod schema for agent_chat account configuration.
 * DB credentials (host, port, database, user, password) are read from
 * ~/.openclaw/postgres.json at runtime — they are not required here.
 */
export const AgentChatAccountSchemaBase = z
  .object({
    name: z.string().optional(),
    enabled: z.boolean().optional(),
    pollIntervalMs: z.number().int().positive().optional().default(1000),
  })
  .strict();

export const AgentChatAccountSchema = AgentChatAccountSchemaBase;

// Create the full config schema with accounts - use passthrough to avoid strict schema issues
const AgentChatFullSchema = z.object({
  name: z.string().optional(),
  enabled: z.boolean().optional(),
  pollIntervalMs: z.number().int().positive().optional().default(1000),
  accounts: z.record(z.string(), AgentChatAccountSchema.optional()).optional(),
}).passthrough();

// Manually construct the ChannelConfigSchema to avoid Zod type casting issues
export const AgentChatConfigSchema: ChannelConfigSchema = {
  schema: {
    type: "object",
    properties: {
      name: { type: "string" },
      enabled: { type: "boolean" },
      pollIntervalMs: { type: "integer", default: 1000 },
      accounts: {
        type: "object",
        additionalProperties: {
          type: "object",
          properties: {
            name: { type: "string" },
            enabled: { type: "boolean" },
            pollIntervalMs: { type: "integer" },
          },
        },
      },
    },
    required: [],
  },
};

export type ResolvedAgentChatAccount = {
  accountId: string;
  name: string;
  enabled: boolean;
  config: {
    pollIntervalMs: number;
  };
};
