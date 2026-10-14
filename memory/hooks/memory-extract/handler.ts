/**
 * Legacy internal-hook wrapper for memory-extract.
 *
 * The implementation has moved to the shared core at
 * memory/plugins/memory-extract/src/extraction.ts.  This file remains a
 * thin async handler so existing legacy loader deployments continue to work
 * until the installer migrates them to the plugin (nova-mind#726).
 */

import {
  handleMessage,
  setModuleLogger,
  createDefaultLogger,
} from "../../../memory/plugins/memory-extract/src/extraction.ts";

export default async function handler(event: any): Promise<void> {
  setModuleLogger(createDefaultLogger());
  return handleMessage(event);
}
