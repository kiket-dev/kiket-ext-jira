const CASE_ID_PATTERN =
  /(?:kiket-case|caseId|case)\s*[:=]\s*([0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12})/i;

export function recordField(payload: Record<string, unknown>, key: string): Record<string, unknown> {
  const value = payload[key];
  return value && typeof value === 'object' && !Array.isArray(value) ? (value as Record<string, unknown>) : {};
}

export function stringField(payload: Record<string, unknown>, key: string): string | undefined {
  const value = payload[key];
  return typeof value === 'string' && value.length > 0 ? value : undefined;
}

export function resolveCaseId(...sources: unknown[]): string | undefined {
  for (const source of sources) {
    if (typeof source !== 'string') continue;
    const match = source.match(CASE_ID_PATTERN);
    if (match?.[1]) return match[1];
  }
  return undefined;
}

export function normalizeSourceTime(value: unknown, fallback: Date): Date {
  if (typeof value === 'number') {
    const parsed = new Date(value);
    return Number.isNaN(parsed.getTime()) ? fallback : parsed;
  }
  if (typeof value !== 'string') return fallback;
  const parsed = new Date(value);
  return Number.isNaN(parsed.getTime()) ? fallback : parsed;
}

export function deliveryId(metadata: Record<string, unknown> | undefined): string | undefined {
  if (!metadata) return undefined;
  const value = metadata.deliveryId;
  return typeof value === 'string' && value.length > 0 ? value : undefined;
}

export function actorFromUser(user: Record<string, unknown>): Record<string, unknown> {
  const accountId = stringField(user, 'accountId');
  const displayName = stringField(user, 'displayName');
  const email = stringField(user, 'emailAddress');
  return {
    ...(accountId ? { accountId } : {}),
    ...(displayName ? { displayName } : {}),
    ...(email ? { email } : {}),
  };
}

export function issueKey(issue: Record<string, unknown>): string | undefined {
  return stringField(issue, 'key') ?? stringField(issue, 'id');
}

export function issueStatusName(issue: Record<string, unknown>): string | undefined {
  const fields = recordField(issue, 'fields');
  const status = recordField(fields, 'status');
  return stringField(status, 'name');
}

export function issueAssignee(issue: Record<string, unknown>): Record<string, unknown> | undefined {
  const fields = recordField(issue, 'fields');
  const assignee = recordField(fields, 'assignee');
  return Object.keys(assignee).length > 0 ? actorFromUser(assignee) : undefined;
}

export function issueSummary(issue: Record<string, unknown>): string | undefined {
  const fields = recordField(issue, 'fields');
  return stringField(fields, 'summary');
}

export function issueDescription(issue: Record<string, unknown>): string | undefined {
  const fields = recordField(issue, 'fields');
  return stringField(fields, 'description');
}

export function issueUpdatedAt(issue: Record<string, unknown>): unknown {
  const fields = recordField(issue, 'fields');
  return fields.updated ?? fields.created;
}

export function statusChangeFromChangelog(payload: Record<string, unknown>): {
  fromStatus?: string;
  toStatus?: string;
} {
  const changelog = recordField(payload, 'changelog');
  const items = changelog.items;
  if (!Array.isArray(items)) return {};
  for (const item of items) {
    if (!item || typeof item !== 'object') continue;
    const record = item as Record<string, unknown>;
    if (record.field !== 'status') continue;
    return {
      fromStatus: stringField(record, 'fromString'),
      toStatus: stringField(record, 'toString'),
    };
  }
  return {};
}
