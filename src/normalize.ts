import type { JiraRawEventContext, NormalizedOperationalEventOutput } from './types.js';
import {
  actorFromUser,
  deliveryId,
  issueAssignee,
  issueDescription,
  issueKey,
  issueStatusName,
  issueSummary,
  issueUpdatedAt,
  normalizeSourceTime,
  recordField,
  resolveCaseId,
  statusChangeFromChangelog,
  stringField,
} from './utils.js';

function baseFields(ctx: JiraRawEventContext) {
  return {
    organizationId: ctx.organizationId,
    workspaceId: ctx.workspaceId ?? undefined,
    processId: ctx.processId ?? undefined,
    correlationIds: [ctx.rawEventId, ctx.idempotencyKey],
    sourceSystem: 'jira' as const,
  };
}

function normalizeIssueLifecycle(ctx: JiraRawEventContext): NormalizedOperationalEventOutput {
  const payload = ctx.payload;
  const issue = recordField(payload, 'issue');
  const user = recordField(payload, 'user');
  const key = issueKey(issue);
  if (!key) throw new Error('Missing required field: issueKey');

  const caseId = resolveCaseId(payload.caseId, issueDescription(issue), issueSummary(issue));
  if (!caseId) throw new Error('Missing required field: caseId');

  const status = issueStatusName(issue);
  const assignee = issueAssignee(issue);
  const statusChange = statusChangeFromChangelog(payload);
  const occurredAt = normalizeSourceTime(payload.timestamp ?? issueUpdatedAt(issue), ctx.receivedAt);
  const actor = actorFromUser(user);
  const delivery = deliveryId(ctx.metadata);
  const summary = issueSummary(issue) ?? key;

  return {
    ...baseFields(ctx),
    caseId,
    eventType: 'case.updated',
    sourceObjectId: key,
    actor,
    subject: { type: 'jira_issue', id: key, caseId, status },
    occurredAt,
    attributes: {
      status,
      assignee,
      statusChange,
      webhookEvent: stringField(payload, 'webhookEvent') ?? ctx.sourceEventType,
      deliveryId: delivery,
    },
    dedupeKey: `jira:issue:${key}:${ctx.sourceEventType}`,
    evidence: [
      {
        evidenceType: 'jira_issue',
        title: summary,
        sourceObjectId: key,
        capturedAt: occurredAt,
        payload: {
          key,
          status,
          assignee,
          statusChange,
          summary,
          webhookEvent: stringField(payload, 'webhookEvent') ?? ctx.sourceEventType,
          deliveryId: delivery,
        },
        dedupeKey: `jira:evidence:issue:${key}`,
      },
    ],
    intents: [
      {
        type: 'case.link_external_evidence',
        targetType: 'case',
        targetId: caseId,
        reason: 'Jira issue lifecycle produced evidence for a linked operational case.',
        attributes: { evidenceType: 'jira_issue', sourceObjectId: key },
        idempotencyKey: `jira:intent:link:${key}:${caseId}`,
      },
    ],
  };
}

function normalizeCommentCreated(ctx: JiraRawEventContext): NormalizedOperationalEventOutput {
  const payload = ctx.payload;
  const issue = recordField(payload, 'issue');
  const comment = recordField(payload, 'comment');
  const user = recordField(payload, 'user');
  const author = recordField(comment, 'author');
  const key = issueKey(issue);
  if (!key) throw new Error('Missing required field: issueKey');

  const caseId = resolveCaseId(payload.caseId, issueDescription(issue), stringField(comment, 'body'));
  if (!caseId) throw new Error('Missing required field: caseId');

  const commentId = stringField(comment, 'id') ?? ctx.idempotencyKey;
  const sourceObjectId = `${key}:comment:${commentId}`;
  const occurredAt = normalizeSourceTime(comment.created ?? payload.timestamp, ctx.receivedAt);
  const actor = Object.keys(author).length > 0 ? actorFromUser(author) : actorFromUser(user);
  const delivery = deliveryId(ctx.metadata);
  const bodyPreview = stringField(comment, 'body')?.slice(0, 500);

  return {
    ...baseFields(ctx),
    caseId,
    eventType: 'evidence.observed',
    sourceObjectId,
    actor,
    subject: { type: 'jira_comment', id: commentId, issueKey: key, caseId },
    occurredAt,
    attributes: {
      issueKey: key,
      deliveryId: delivery,
    },
    dedupeKey: `jira:comment:${commentId}:created`,
    evidence: [
      {
        evidenceType: 'jira_comment',
        title: `Jira comment on ${key}`,
        sourceObjectId,
        capturedAt: occurredAt,
        payload: {
          issueKey: key,
          commentId,
          bodyPreview,
          actor,
          deliveryId: delivery,
        },
        dedupeKey: `jira:evidence:comment:${commentId}`,
      },
    ],
    intents: [
      {
        type: 'case.link_external_evidence',
        targetType: 'case',
        targetId: caseId,
        reason: 'Jira comment produced evidence for a linked operational case.',
        attributes: { evidenceType: 'jira_comment', sourceObjectId },
        idempotencyKey: `jira:intent:comment:${commentId}:${caseId}`,
      },
    ],
  };
}

export function normalizeJiraRawEvent(ctx: JiraRawEventContext): NormalizedOperationalEventOutput {
  const webhookEvent = stringField(ctx.payload, 'webhookEvent') ?? ctx.sourceEventType;
  if (webhookEvent === 'comment_created' || webhookEvent === 'jira:comment_created') {
    return normalizeCommentCreated(ctx);
  }
  if (
    webhookEvent === 'jira:issue_created' ||
    webhookEvent === 'jira:issue_updated' ||
    webhookEvent === 'issue_created' ||
    webhookEvent === 'issue_updated'
  ) {
    return normalizeIssueLifecycle(ctx);
  }
  throw new Error(`Unsupported Jira event for core normalization: ${webhookEvent}`);
}

export const JIRA_ADAPTER_SOURCE_EVENT_TYPES = ['jira:issue_created', 'jira:issue_updated', 'comment_created'] as const;

export const JIRA_ADAPTER_EVIDENCE_TYPES = ['jira_issue', 'jira_comment'] as const;
