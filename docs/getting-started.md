# Getting Started with Jira Integration

Bi-directional sync between Kiket and Jira for teams migrating or working across both platforms.

## Prerequisites

- Jira Cloud or Data Center instance
- Admin access to create API tokens

## Step 1: Create Jira API Token

1. Go to [Atlassian Account Settings](https://id.atlassian.com/manage-profile/security/api-tokens)
2. Click **Create API token**
3. Name it "Kiket Integration" and copy the token

## Step 2: Configure in Kiket

1. Go to **Organization Settings → Extensions → Jira**
2. Enter:
   - **Jira URL**: `https://your-domain.atlassian.net`
   - **Email**: Your Atlassian account email
   - **API Token**: The token you created
3. Click **Test Connection**

## Step 3: Map Projects

1. Select which Jira projects to sync
2. Map Jira issue types to Kiket issue types
3. Map status fields for bi-directional updates

## Step 4: Enable Sync

```yaml
automations:
  - name: sync_to_jira
    trigger:
      event: issue.created
      conditions:
        - field: project.settings.jira_sync
          operator: eq
          value: true
    actions:
      - extension: dev.kiket.ext.jira
        command: jira.createIssue
        params:
          project_key: "{{ project.settings.jira_project }}"
          issue_type: "{{ issue.type | jira_type_map }}"
```

## Sync Modes

- **Mirror**: Full bi-directional sync (changes in either system update the other)
- **Push**: Kiket → Jira only
- **Pull**: Jira → Kiket only
