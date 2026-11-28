/**
 * Minimal type declarations for the host OpenClaw plugin SDK.
 *
 * The plugin's published openclaw peer/dev dependency (2026.2.9) does not
 * ship plugin-sdk types, so these stubs satisfy the TypeScript build while
 * the real types are provided by the host gateway at runtime.
 */

declare module "openclaw/plugin-sdk" {
  export type OpenClawPluginApi = {
    id: string;
    pluginConfig?: Record<string, unknown>;
    config: Record<string, unknown>;
    logger: {
      debug?: (msg: string) => void;
      info: (msg: string) => void;
      warn: (msg: string) => void;
      error: (msg: string) => void;
    };
    registerService: (service: unknown) => void;
  };

  export type OpenClawPluginServiceContext = {
    logger: OpenClawPluginApi["logger"];
  };
}
