import { readFileSync } from 'node:fs';
import { describe, expect, it } from 'vitest';

describe('kiket-extension.yaml', () => {
  it('declares a kiket.dev/v1 Extension manifest for Jira', () => {
    const yaml = readFileSync(new URL('../kiket-extension.yaml', import.meta.url), 'utf8');
    expect(yaml).toContain('apiVersion: kiket.dev/v1');
    expect(yaml).toContain('kind: Extension');
    expect(yaml).toContain('key: kiket-ext-jira');
    expect(yaml).toContain('sourceSystem: jira');
  });
});
