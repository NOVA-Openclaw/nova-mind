import { defineConfig } from "vitest/config";

export default defineConfig({
  test: {
    // Only run the vitest-specific tests; existing suites use node:test.
    include: ["vitest-tests/**/*.vitest.test.ts"],
    // Run one file at a time in a single fork so the logs show exactly one
    // worker regardless of host CPU count. --maxWorkers=1 alone still spawned
    // multiple workers in CI; singleFork enforces the actual intent.
    pool: "forks",
    singleFork: true,
    fileParallelism: false,
    maxWorkers: 1,
    minWorkers: 1,
  },
});
