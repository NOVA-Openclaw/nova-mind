import { defineConfig } from "vitest/config";

export default defineConfig({
  test: {
    // Only run the vitest-specific tests; existing suites use node:test.
    include: ["vitest-tests/**/*.vitest.test.ts"],
    // Run all vitest test files in a single worker/fork so the logs show
    // exactly one worker regardless of host CPU count. --maxWorkers=1 and
    // --no-file-parallelism alone still spawned one fork per file in Vitest 5;
    // isolate:false reuses one worker process across files while keeping the
    // default forks pool. fileParallelism:false keeps file scheduling serial.
    pool: "forks",
    isolate: false,
    fileParallelism: false,
    maxWorkers: 1,
    minWorkers: 1,
  },
});
