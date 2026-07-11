import { defineConfig } from "vitest/config"
import { resolve, dirname } from "path"
import { fileURLToPath } from "url"

const __dirname = dirname(fileURLToPath(import.meta.url))

export default defineConfig({
  test: {
    environment: "jsdom",
    include: ["spec/javascript/**/*.test.js"],
    // Forks over the default threads pool: jsdom state accumulates per WORKER
    // across test files, and the suite has grown past the point where a
    // long-lived worker hits node's heap ceiling (OOM + ERR_IPC_CHANNEL_CLOSED
    // mid-run). Process-isolated forks reclaim each file's memory on exit.
    pool: "forks",
  },
  resolve: {
    alias: [
      // Bare importmap specifiers → app source directories.
      // Regex aliases let us match "pito/reveal_queue", "pito/typing", etc.
      {
        find: /^pito\//,
        replacement: resolve(__dirname, "app/javascript/pito") + "/",
      },
      {
        find: /^controllers\//,
        replacement: resolve(__dirname, "app/javascript/controllers") + "/",
      },
      {
        // Turbo Rails stub — controllers that import Turbo won't execute it in tests.
        find: "@hotwired/turbo-rails",
        replacement: resolve(__dirname, "spec/javascript/support/turbo_stub.js"),
      },
      // @hotwired/stimulus resolves from node_modules automatically.
    ],
  },
})
