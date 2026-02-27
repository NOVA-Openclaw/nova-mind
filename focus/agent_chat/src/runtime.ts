import type { PluginRuntime } from "openclaw/plugin-sdk";

let runtime: PluginRuntime | null = null;

export function setAgentChatRuntime(next: PluginRuntime) {
  runtime = next;
}

export function getAgentChatRuntime(): PluginRuntime {
  if (!runtime) {
    throw new Error("Agent Chat runtime not initialized");
  }
  return runtime;
}
