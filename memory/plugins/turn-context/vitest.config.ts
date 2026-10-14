import { defineConfig } from "vitest/config";

export default defineConfig({
  test: {
    // Only run the vitest-specific tests; existing suites use node:test.
    include: ["vitest-tests/**/*.vitest.test.ts"],
    // Run all vitest test files in a single worker/fork so the logs show
    // exactly one worker regardless of host CPU count. --maxWorkers=1 and
    // --no-file-parallelism alone still spawned one fork per file in Vitest 5;
    // isolate:true keeps each test file's module mocks independent (required
    // now that memory-extract-703 and memory-extract-708 both mock
    // child_process). fileParallelism:false keeps file scheduling serial.
    pool: "forks",
    isolate: true,
    fileParallelism: false,
    maxWorkers: 1,
    minWorkers: 1,
  },
});
