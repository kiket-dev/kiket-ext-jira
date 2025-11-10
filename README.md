# kiket-ext-jira

Jira Integration Extension for Kiket - Bidirectional issue sync, status/field mapping, attachment mirroring, and workflow automation between Jira and Kiket.

## Features

- **Project Registration**: Connect Jira projects to Kiket projects
- **Bidirectional Issue Sync**: Sync issues between Jira and Kiket
- **Field Mapping**: Map custom fields between platforms
- **Status Mapping**: Map workflow statuses for seamless transitions
- **Attachment Mirroring**: Sync attachments bidirectionally
- **Comment Synchronization**: Keep comments in sync
- **Webhook Integration**: Real-time updates from Jira
- **Sync Jobs**: Manual and scheduled sync operations
- **Analytics**: dbt models for sync metrics and insights
- **CSV Export**: Export mappings and sync data

## Installation

### Prerequisites

- Ruby 3.4+
- Bundler
- Jira Cloud or Server instance
- Jira API token
- Access to Kiket custom_data module

### Setup

```bash
cd extensions/jira
bundle install
```

### Environment Variables

Create a `.env` file:

```bash
RACK_ENV=development
PORT=9393

# Jira Configuration
JIRA_URL=https://your-company.atlassian.net
JIRA_EMAIL=your-email@company.com
JIRA_API_TOKEN=your_api_token_here
JIRA_WEBHOOK_SECRET=your_webhook_secret
```

### Jira API Token

1. Go to https://id.atlassian.com/manage-profile/security/api-tokens
2. Click "Create API token"
3. Give it a name and copy the token
4. Use your Jira email and token for authentication

### Running Locally

```bash
bundle exec puma -C puma.rb
```

The extension will be available at `http://localhost:9393`.

## API Endpoints

### Health Check

**GET /health**

Returns extension health status.

### Project Management

**POST /projects/register**

Register a Jira project with Kiket.

Request:
```json
{
  "jira_project_key": "PROJ",
  "jira_project_id": "10000",
  "jira_url": "https://company.atlassian.net",
  "kiket_project_id": "proj-123",
  "sync_enabled": true,
  "sync_direction": "bidirectional",
  "sync_comments": true,
  "sync_attachments": true,
  "auto_create_mappings": false
}
```

**GET /projects**

List registered projects. Filter by `kiket_project_id`.

**GET /projects/:id**

Get project details.

**DELETE /projects/:id**

Unregister a project.

### Issue Mapping

**POST /issues/map**

Create issue mapping between Jira and Kiket.

Request:
```json
{
  "project_id": 1,
  "jira_issue_key": "PROJ-123",
  "jira_issue_id": "10001",
  "kiket_issue_id": "ISSUE-456",
  "sync_enabled": true
}
```

**GET /issues/mappings**

List mappings. Filter by `project_id`, `kiket_issue_id`, or `jira_issue_key`.

**PUT /issues/mappings/:id**

Update mapping sync settings.

**DELETE /issues/mappings/:id**

Remove mapping.

### Field Mapping

**POST /fields/map**

Map a Jira custom field to Kiket field.

Request:
```json
{
  "project_id": 1,
  "jira_field_id": "customfield_10001",
  "jira_field_name": "Story Points",
  "kiket_field_name": "effort",
  "field_type": "number",
  "sync_direction": "bidirectional"
}
```

**GET /fields/mappings**

List field mappings for a project.

**DELETE /fields/mappings/:id**

Remove field mapping.

### Status Mapping

**POST /status/map**

Map Jira status to Kiket status.

Request:
```json
{
  "project_id": 1,
  "jira_status_id": "10001",
  "jira_status_name": "In Progress",
  "kiket_status": "in_progress",
  "sync_on_transition": true
}
```

**GET /status/mappings**

List status mappings.

**DELETE /status/mappings/:id**

Remove status mapping.

### Issue Synchronization

**POST /sync/issue**

Manually sync a specific issue.

Request:
```json
{
  "mapping_id": 1,
  "direction": "bidirectional"
}
```

Directions: `jira_to_kiket`, `kiket_to_jira`, `bidirectional`

### Attachment Management

**POST /attachments/mirror**

Mirror an attachment between platforms.

Request:
```json
{
  "mapping_id": 1,
  "jira_attachment_id": "12345",
  "kiket_attachment_id": "att-789",
  "filename": "document.pdf",
  "file_size": 102400,
  "mime_type": "application/pdf",
  "direction": "jira_to_kiket"
}
```

**GET /attachments**

List mirrored attachments for a mapping.

### Sync Jobs

**POST /sync/trigger**

Trigger a sync job.

Request:
```json
{
  "project_id": 1,
  "sync_type": "full",
  "sync_direction": "bidirectional"
}
```

Sync types: `full`, `incremental`, `issues_only`, `mappings_only`

**GET /sync/jobs**

List sync jobs. Filter by `project_id` and `status`.

**GET /sync/jobs/:id**

Get sync job details.

### Webhooks

**POST /webhooks/jira**

Receives Jira webhooks. Supported events:
- `jira:issue_created`
- `jira:issue_updated`
- `jira:issue_deleted`
- `comment_created`
- `comment_updated`

**POST /webhooks/kiket/issue_transitioned**

Handle Kiket issue status changes and sync to Jira.

**GET /webhooks/deliveries**

List webhook delivery history.

### Reports

**GET /reports/sync_metrics**

Get sync job metrics and statistics.

Response:
```json
{
  "total_jobs": 50,
  "successful_jobs": 45,
  "failed_jobs": 5,
  "success_rate": 90.0,
  "total_issues_synced": 500,
  "total_comments_synced": 150,
  "total_attachments_synced": 75,
  "active_mappings": 100
}
```

**GET /reports/mapping_status**

Get mapping statistics.

### Export

**GET /export/mappings/csv**

Export issue mappings as CSV.

## Custom Data Schema

The extension uses seven custom data tables:

### projects

Stores registered Jira projects.

| Column | Type | Description |
|--------|------|-------------|
| jira_project_key | string | Jira project key (e.g., "PROJ") |
| jira_url | string | Jira instance URL |
| kiket_project_id | string | Associated Kiket project |
| sync_direction | string | Sync direction (bidirectional/one-way) |
| sync_comments | boolean | Sync comments |
| sync_attachments | boolean | Sync attachments |
| auto_create_mappings | boolean | Auto-create issue mappings |

### issue_mappings

Maps Jira issues to Kiket issues.

| Column | Type | Description |
|--------|------|-------------|
| jira_issue_key | string | Jira issue key (e.g., "PROJ-123") |
| kiket_issue_id | string | Kiket issue ID |
| sync_enabled | boolean | Whether sync is active |
| last_jira_update | timestamp | Last Jira modification |
| last_kiket_update | timestamp | Last Kiket modification |
| last_synced_at | timestamp | Last successful sync |

### field_mappings

Maps custom fields between platforms.

| Column | Type | Description |
|--------|------|-------------|
| jira_field_id | string | Jira field ID (e.g., "customfield_10001") |
| jira_field_name | string | Jira field name |
| kiket_field_name | string | Kiket field name |
| field_type | string | Field data type |
| transform_function | text | Optional transformation logic |
| sync_direction | string | Sync direction |

### status_mappings

Maps workflow statuses.

| Column | Type | Description |
|--------|------|-------------|
| jira_status_id | string | Jira status ID |
| jira_status_name | string | Jira status name |
| kiket_status | string | Kiket status |
| sync_on_transition | boolean | Sync when status changes |

### sync_jobs

Tracks synchronization jobs.

| Column | Type | Description |
|--------|------|-------------|
| sync_type | string | Type of sync |
| sync_direction | string | Direction of sync |
| status | string | Job status |
| issues_processed | integer | Issues synced |
| comments_synced | integer | Comments synced |
| attachments_synced | integer | Attachments synced |

### webhook_deliveries

Logs Jira webhook deliveries.

| Column | Type | Description |
|--------|------|-------------|
| webhook_event | string | Jira event type |
| issue_key | string | Related issue key |
| received_at | timestamp | Receipt time |
| processed | boolean | Processing status |
| error | text | Error message if failed |

### attachments

Tracks mirrored attachments.

| Column | Type | Description |
|--------|------|-------------|
| jira_attachment_id | string | Jira attachment ID |
| kiket_attachment_id | string | Kiket attachment ID |
| filename | string | File name |
| file_size | bigint | Size in bytes |
| direction | string | Mirror direction |

## Analytics Models

The extension provides three dbt models:

### sync_metrics_daily

Incremental model tracking daily sync performance.

Metrics:
- Total jobs, successful/failed counts
- Issues, comments, attachments synced
- Average job duration
- Success rate percentage

### project_summary

Summary statistics per Jira project.

Metrics:
- Total and active mappings
- Field and status mappings count
- Job success rate
- Last sync timestamps

### webhook_processing

Webhook delivery reliability by event type.

Metrics:
- Total deliveries per event
- Success/failure counts
- Success rate percentage

### Dashboard

The `jira_overview` dashboard provides:
- Summary metrics (projects, mappings, jobs, success rate)
- Daily sync job trends
- Project sync status table
- Webhook processing reliability

## Command Palette

The extension contributes these commands (⌘K / Ctrl+K):

- **Sync with Jira**: Trigger sync for current issue
- **Map to Jira Issue**: Create mapping to existing Jira issue
- **View in Jira**: Open mapped Jira issue
- **Sync Jira Project**: Trigger full project sync
- **Export Mappings**: Export issue mappings as CSV

## Jira Webhook Setup

1. Go to Jira Settings → System → WebHooks
2. Create a new webhook
3. URL: `https://your-extension.com/webhooks/jira`
4. Events: Select issue and comment events
5. Secret: Optional, for signature verification

## Usage Examples

### Register Project

```bash
curl -X POST http://localhost:9393/projects/register \
  -H "Content-Type: application/json" \
  -d '{
    "jira_project_key": "PROJ",
    "kiket_project_id": "proj-123",
    "jira_url": "https://company.atlassian.net"
  }'
```

### Create Issue Mapping

```bash
curl -X POST http://localhost:9393/issues/map \
  -H "Content-Type: application/json" \
  -d '{
    "project_id": 1,
    "jira_issue_key": "PROJ-123",
    "kiket_issue_id": "ISSUE-456"
  }'
```

### Trigger Full Sync

```bash
curl -X POST http://localhost:9393/sync/trigger \
  -H "Content-Type: application/json" \
  -d '{
    "project_id": 1,
    "sync_type": "full"
  }'
```

## Development

### Running Tests

```bash
bundle exec rspec
```

### Linting

```bash
bundle exec rubocop
```

### Docker

```bash
docker build -t kiket-ext-jira .
docker run -p 9393:9393 -e JIRA_URL=https://company.atlassian.net kiket-ext-jira
```

## Troubleshooting

### Sync Not Working

- Verify project is registered
- Check sync_enabled is true
- Verify Jira API credentials
- Review sync job errors

### Webhook Not Processing

- Verify webhook URL is accessible
- Check webhook secret matches
- Review delivery logs in Jira

### Field Mapping Fails

- Ensure field IDs are correct
- Check field types are compatible
- Verify transform function syntax

## Security

- Store Jira API token in encrypted secrets
- Use HTTPS for webhook endpoints
- Validate webhook signatures
- Implement rate limiting

## Permissions

- **user**: View mappings and sync status
- **manager**: Create/update mappings, trigger syncs
- **admin**: Full access including deletion

## Support

For issues and questions, refer to Kiket documentation or open an issue in the repository.

## License

Part of the Kiket platform.