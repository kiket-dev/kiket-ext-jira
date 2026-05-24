import { describe, expect, it } from 'vitest';
import { JIRA_ADAPTER_SOURCE_EVENT_TYPES, normalizeJiraRawEvent } from '../src/index.js';

describe('jira extension entry', () => {
  it('re-exports jira-adapter normalizers', () => {
    expect(JIRA_ADAPTER_SOURCE_EVENT_TYPES).toContain('jira:issue_updated');
    expect(typeof normalizeJiraRawEvent).toBe('function');
  });
});
