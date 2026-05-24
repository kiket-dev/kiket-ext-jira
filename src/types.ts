export interface JiraRawEventContext {
  organizationId: string;
  workspaceId?: string | null;
  processId?: string | null;
  rawEventId: string;
  idempotencyKey: string;
  sourceEventType: string;
  receivedAt: Date;
  payload: Record<string, unknown>;
  metadata?: Record<string, unknown>;
}

export interface NormalizedOperationalEventOutput {
  organizationId: string;
  workspaceId?: string;
  processId?: string;
  caseId?: string;
  eventType: string;
  sourceSystem: 'jira';
  sourceObjectId?: string;
  actor: Record<string, unknown>;
  subject: Record<string, unknown>;
  occurredAt: Date;
  correlationIds: string[];
  attributes: Record<string, unknown>;
  dedupeKey: string;
  evidence: Array<{
    evidenceType: string;
    title: string;
    sourceObjectId?: string;
    capturedAt: Date;
    payload: Record<string, unknown>;
    dedupeKey: string;
  }>;
  intents: Array<{
    type: string;
    targetType?: string;
    targetId?: string;
    reason: string;
    attributes: Record<string, unknown>;
    idempotencyKey: string;
  }>;
}
