import type { OpenClawPluginApi } from "openclaw/plugin-sdk";
import { createRequire } from "node:module";
import { agentChatPlugin } from "./src/channel.js";
import { setAgentChatRuntime } from "./src/runtime.js";
import { AgentChatConfigSchema } from "./src/config.js";

const plugin = {
  id: "agent_chat",
  name: "Agent Chat",
  description: "PostgreSQL-based inter-agent communication channel",
  configSchema: AgentChatConfigSchema,
  register(api: OpenClawPluginApi) {
    const log = api.logger!;

    // --- Pre-flight: verify 'pg' dependency is resolvable (ESM-compatible) ---
    try {
      const require = createRequire(import.meta.url);
      require.resolve("pg");
      log.debug?.("agent_chat: pg dependency resolved successfully");
    } catch {
      log.error(
        "agent_chat: FATAL — 'pg' module not found. " +
        "Install it with: cd ~/.openclaw && npm install pg --save " +
        "(or re-run the nova-cognition installer). Plugin will NOT function.",
      );
      return; // Bail out — registering without pg would just cause runtime errors
    }

    setAgentChatRuntime(api.runtime);
    api.registerChannel({ plugin: agentChatPlugin });

    // --- Post-registration self-check ---
    const hasOutbound = typeof agentChatPlugin.outbound?.sendText === "function";
    const hasGateway = typeof agentChatPlugin.gateway?.startAccount === "function";

    if (hasOutbound && hasGateway) {
      log.info(
        "agent_chat: registered — outbound (sendText) ✅  inbound (gateway) ✅",
      );
    } else {
      const missing: string[] = [];
      if (!hasOutbound) missing.push("outbound/sendText");
      if (!hasGateway) missing.push("gateway/startAccount");
      log.warn(
        `agent_chat: registered with MISSING capabilities: ${missing.join(", ")}. ` +
        "The plugin may not function correctly.",
      );
    }
  },
};

export default plugin;
