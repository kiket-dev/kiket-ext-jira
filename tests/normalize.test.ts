import { describe, expect, it } from 'vitest';
import { normalizeJiraRawEvent } from '../src/normalize.js';

const CASE_ID = '11111111-1111-4111-8111-111111111111';
const receivedAt = new Date('2026-05-22T10:00:01.000Z');

function baseContext(overrides: Partial<Parameters<typeof normalizeJiraRawEvent>[0]> = {}) {
  return {
    organizationId: 'org-1',
    workspaceId: 'ws-1',
    processId: 'proc-1',
    rawEventId: 'raw-1',
    idempotencyKey: 'idem-1',
    sourceEventType: 'jira:issue_updated',
    receivedAt,
    payload: {},
    metadata: { deliveryId: 'delivery-1' },
    ...overrides,
  };
}

describe('normalizeJiraRawEvent', () => {
  it('normalizes issue lifecycle updates', () => {
    const normalized = normalizeJiraRawEvent(
      baseContext({
        payload: {
          webhookEvent: 'jira:issue_updated',
          issue: {
            key: 'OPS-42',
            fields: {
              summary: 'Access review',
              description: `case: ${CASE_ID}`,
              status: { name: 'In Progress' },
              updated: '2026-05-22T11:00:00.000Z',
            },
          },
        },
      }),
    );

    expect(normalized.eventType).toBe('case.updated');
    expect(normalized.caseId).toBe(CASE_ID);
    expect(normalized.evidence[0]?.evidenceType).toBe('jira_issue');
  });

  it('normalizes created comments', () => {
    const normalized = normalizeJiraRawEvent(
      baseContext({
        sourceEventType: 'comment_created',
        payload: {
          webhookEvent: 'comment_created',
          issue: {
            key: 'OPS-42',
            fields: { description: `case: ${CASE_ID}` },
          },
          comment: {
            id: '10001',
            body: 'LGTM',
            created: '2026-05-22T12:00:00.000Z',
          },
        },
      }),
    );

    expect(normalized.eventType).toBe('evidence.observed');
    expect(normalized.caseId).toBe(CASE_ID);
    expect(normalized.evidence[0]?.evidenceType).toBe('jira_comment');
  });
});
