import { describe, expect, it } from 'vitest';
import { normalizeJiraRawEvent } from '../src/normalize.js';

const CASE_ID = '22222222-2222-4222-8222-222222222222';
const receivedAt = new Date('2026-04-25T10:00:01.000Z');

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
  it('normalizes issue updated events with status change evidence', () => {
    const normalized = normalizeJiraRawEvent(
      baseContext({
        payload: {
          webhookEvent: 'jira:issue_updated',
          timestamp: '2026-04-25T11:00:00.000Z',
          user: { accountId: 'user-1', displayName: 'Alex Owner' },
          issue: {
            key: 'ENG-42',
            fields: {
              summary: 'Deploy billing service',
              description: `case: ${CASE_ID}`,
              status: { name: 'In Progress' },
              assignee: { accountId: 'user-1', displayName: 'Alex Owner' },
              updated: '2026-04-25T11:00:00.000Z',
            },
          },
          changelog: {
            items: [{ field: 'status', fromString: 'To Do', toString: 'In Progress' }],
          },
        },
      }),
    );

    expect(normalized.eventType).toBe('case.updated');
    expect(normalized.caseId).toBe(CASE_ID);
    expect(normalized.sourceObjectId).toBe('ENG-42');
    expect(normalized.attributes.statusChange).toEqual({ fromStatus: 'To Do', toStatus: 'In Progress' });
    expect(normalized.evidence[0]?.evidenceType).toBe('jira_issue');
  });

  it('normalizes comment created events into evidence', () => {
    const normalized = normalizeJiraRawEvent(
      baseContext({
        sourceEventType: 'comment_created',
        payload: {
          webhookEvent: 'comment_created',
          issue: {
            key: 'ENG-7',
            fields: {
              summary: 'Incident follow-up',
              description: `kiket-case: ${CASE_ID}`,
            },
          },
          comment: {
            id: '10001',
            body: 'Remediation complete — caseId: ignored',
            created: '2026-04-25T12:00:00.000Z',
            author: { accountId: 'user-2', displayName: 'Reviewer' },
          },
        },
      }),
    );

    expect(normalized.eventType).toBe('evidence.observed');
    expect(normalized.caseId).toBe(CASE_ID);
    expect(normalized.evidence[0]?.evidenceType).toBe('jira_comment');
  });

  it('rejects unsupported webhook events', () => {
    expect(() =>
      normalizeJiraRawEvent(
        baseContext({
          sourceEventType: 'project_updated',
          payload: { webhookEvent: 'project_updated' },
        }),
      ),
    ).toThrow(/Unsupported Jira event/);
  });
});
