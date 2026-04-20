import { describe, it, expect } from 'vitest';

describe('canary', () => {
  it('should pass a basic assertion', () => {
    expect(1 + 1).toBe(2);
  });

  it('should have access to the test environment', () => {
    expect(typeof globalThis).toBe('object');
  });
});
