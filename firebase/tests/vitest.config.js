import { defineConfig } from "vitest/config";

export default defineConfig({
  test: {
    // Rules evaluation round-trips to the emulator; the default 5s is tight
    // when a single case seeds fixtures and asserts several writes.
    testTimeout: 20000,
    hookTimeout: 30000,
    // The suites share one emulator project, so they must not interleave.
    fileParallelism: false,
  },
});
