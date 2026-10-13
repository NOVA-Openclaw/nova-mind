import { defineConfig } from "vitest/config";

export default defineConfig({
  test: {
    // Only run the vitest-specific tests; existing suites use node:test.
    include: ["vitest-tests/**/*.vitest.test.ts"],
    maxWorkers: 1,
    minWorkers: 1,
  },
});
