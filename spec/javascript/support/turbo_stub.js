// Minimal stub for @hotwired/turbo-rails so controllers that import Turbo
// can be loaded in the Vitest/jsdom environment without network or a real
// Turbo build.  Extend as needed when tests exercise Turbo-aware behaviour.
export const Turbo = {
  visit: () => {},
  clearCache: () => {},
}

export default Turbo
