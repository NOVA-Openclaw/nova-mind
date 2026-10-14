import { defineConfig } from "vitest/config";

export default defineConfig({
  test: {
    include: ["vitest-tests/**/*.vitest.test.ts"],
    pool: "forks",
    isolate: true,
    fileParallelism: false,
    maxWorkers: 1,
    minWorkers: 1,
  },
});
