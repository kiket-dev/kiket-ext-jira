{{
  config(
    materialized='incremental',
    unique_key=['project_id', 'sync_date']
  )
}}

with daily_syncs as (
  select
    project_id,
    date(created_at) as sync_date,
    count(*) as total_jobs,
    count(case when status = 'completed' then 1 end) as successful_jobs,
    count(case when status = 'failed' then 1 end) as failed_jobs,
    sum(issues_processed) as total_issues_synced,
    sum(comments_synced) as total_comments_synced,
    sum(attachments_synced) as total_attachments_synced,
    avg(case
      when completed_at is not null and started_at is not null
      then extract(epoch from (completed_at - started_at)) / 60
    end) as avg_job_duration_minutes
  from {{ source('jira_data', 'sync_jobs') }}
  where created_at is not null
  {% if is_incremental() %}
    and created_at >= (select max(sync_date) - interval '7 days' from {{ this }})
  {% endif %}
  group by 1, 2
)

select
  project_id,
  sync_date,
  total_jobs,
  successful_jobs,
  failed_jobs,
  total_issues_synced,
  total_comments_synced,
  total_attachments_synced,
  round(cast(avg_job_duration_minutes as numeric), 2) as avg_job_duration_minutes,
  round(100.0 * successful_jobs / nullif(total_jobs, 0), 2) as success_rate_pct
from daily_syncs
