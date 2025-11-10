with project_stats as (
  select
    p.id as project_id,
    p.jira_project_key,
    p.kiket_project_id,
    p.sync_enabled,
    count(distinct im.id) as total_mappings,
    count(distinct case when im.sync_enabled then im.id end) as active_mappings,
    count(distinct fm.id) as field_mappings_count,
    count(distinct sm.id) as status_mappings_count,
    count(distinct sj.id) as total_sync_jobs,
    count(distinct case when sj.status = 'completed' then sj.id end) as successful_jobs,
    max(p.last_synced_at) as last_sync,
    max(im.last_synced_at) as last_issue_sync
  from {{ source('jira_data', 'projects') }} p
  left join {{ source('jira_data', 'issue_mappings') }} im on p.id = im.project_id
  left join {{ source('jira_data', 'field_mappings') }} fm on p.id = fm.project_id
  left join {{ source('jira_data', 'status_mappings') }} sm on p.id = sm.project_id
  left join {{ source('jira_data', 'sync_jobs') }} sj on p.id = sj.project_id
  group by 1, 2, 3, 4
)

select
  project_id,
  jira_project_key,
  kiket_project_id,
  sync_enabled,
  total_mappings,
  active_mappings,
  field_mappings_count,
  status_mappings_count,
  total_sync_jobs,
  successful_jobs,
  round(100.0 * successful_jobs / nullif(total_sync_jobs, 0), 2) as job_success_rate_pct,
  last_sync,
  last_issue_sync
from project_stats
