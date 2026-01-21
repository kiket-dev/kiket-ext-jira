# frozen_string_literal: true

require 'kiket_sdk'
require 'rackup'
require 'json'
require 'faraday'
require 'faraday/multipart'
require 'base64'
require 'logger'

# Jira Integration Extension
# Manages Jira project sync, issue mapping, field/status mapping, and webhooks
class JiraExtension
  REQUIRED_READ_SCOPES = %w[projects:read].freeze
  REQUIRED_WRITE_SCOPES = %w[projects:write].freeze
  REQUIRED_ISSUES_SCOPES = %w[issues:write].freeze
  REQUIRED_SYNC_SCOPES = %w[sync:execute].freeze
  REQUIRED_WEBHOOK_SCOPES = %w[webhooks:receive].freeze

  def initialize
    @sdk = KiketSDK.new
    @logger = Logger.new($stdout)

    # In-memory storage (production would use custom_data tables)
    @projects = {}
    @issue_mappings = {}
    @field_mappings = {}
    @status_mappings = {}
    @sync_jobs = []
    @webhook_deliveries = []
    @attachments = {}

    setup_handlers
  end

  def app
    @sdk
  end

  private

  def setup_handlers
    # Project Management
    @sdk.register('jira.projects.register', version: 'v1', required_scopes: REQUIRED_WRITE_SCOPES) do |payload, context|
      handle_register_project(payload, context)
    end

    @sdk.register('jira.projects.list', version: 'v1', required_scopes: REQUIRED_READ_SCOPES) do |payload, context|
      handle_list_projects(payload, context)
    end

    @sdk.register('jira.projects.get', version: 'v1', required_scopes: REQUIRED_READ_SCOPES) do |payload, context|
      handle_get_project(payload, context)
    end

    @sdk.register('jira.projects.delete', version: 'v1', required_scopes: REQUIRED_WRITE_SCOPES) do |payload, context|
      handle_delete_project(payload, context)
    end

    # Issue Mapping
    @sdk.register('jira.issues.map', version: 'v1', required_scopes: REQUIRED_ISSUES_SCOPES) do |payload, context|
      handle_map_issue(payload, context)
    end

    @sdk.register('jira.issues.mappings.list', version: 'v1', required_scopes: REQUIRED_READ_SCOPES) do |payload, context|
      handle_list_issue_mappings(payload, context)
    end

    @sdk.register('jira.issues.mappings.update', version: 'v1', required_scopes: REQUIRED_ISSUES_SCOPES) do |payload, context|
      handle_update_issue_mapping(payload, context)
    end

    @sdk.register('jira.issues.mappings.delete', version: 'v1', required_scopes: REQUIRED_ISSUES_SCOPES) do |payload, context|
      handle_delete_issue_mapping(payload, context)
    end

    # Field Mapping
    @sdk.register('jira.fields.map', version: 'v1', required_scopes: REQUIRED_WRITE_SCOPES) do |payload, context|
      handle_map_field(payload, context)
    end

    @sdk.register('jira.fields.mappings.list', version: 'v1', required_scopes: REQUIRED_READ_SCOPES) do |payload, context|
      handle_list_field_mappings(payload, context)
    end

    @sdk.register('jira.fields.mappings.delete', version: 'v1', required_scopes: REQUIRED_WRITE_SCOPES) do |payload, context|
      handle_delete_field_mapping(payload, context)
    end

    # Status Mapping
    @sdk.register('jira.status.map', version: 'v1', required_scopes: REQUIRED_WRITE_SCOPES) do |payload, context|
      handle_map_status(payload, context)
    end

    @sdk.register('jira.status.mappings.list', version: 'v1', required_scopes: REQUIRED_READ_SCOPES) do |payload, context|
      handle_list_status_mappings(payload, context)
    end

    @sdk.register('jira.status.mappings.delete', version: 'v1', required_scopes: REQUIRED_WRITE_SCOPES) do |payload, context|
      handle_delete_status_mapping(payload, context)
    end

    # Issue Synchronization
    @sdk.register('jira.sync.issue', version: 'v1', required_scopes: REQUIRED_SYNC_SCOPES) do |payload, context|
      handle_sync_issue(payload, context)
    end

    # Attachment Management
    @sdk.register('jira.attachments.mirror', version: 'v1', required_scopes: REQUIRED_ISSUES_SCOPES) do |payload, context|
      handle_mirror_attachment(payload, context)
    end

    @sdk.register('jira.attachments.list', version: 'v1', required_scopes: REQUIRED_READ_SCOPES) do |payload, context|
      handle_list_attachments(payload, context)
    end

    # Sync Jobs
    @sdk.register('jira.sync.trigger', version: 'v1', required_scopes: REQUIRED_SYNC_SCOPES) do |payload, context|
      handle_trigger_sync(payload, context)
    end

    @sdk.register('jira.sync.jobs.list', version: 'v1', required_scopes: REQUIRED_READ_SCOPES) do |payload, context|
      handle_list_sync_jobs(payload, context)
    end

    @sdk.register('jira.sync.jobs.get', version: 'v1', required_scopes: REQUIRED_READ_SCOPES) do |payload, context|
      handle_get_sync_job(payload, context)
    end

    # Webhooks
    @sdk.register('jira.webhooks.receive', version: 'v1', required_scopes: REQUIRED_WEBHOOK_SCOPES) do |payload, context|
      handle_jira_webhook(payload, context)
    end

    @sdk.register('jira.webhooks.kiket.issue_transitioned', version: 'v1', required_scopes: REQUIRED_WEBHOOK_SCOPES) do |payload, context|
      handle_kiket_issue_transitioned(payload, context)
    end

    @sdk.register('jira.webhooks.deliveries', version: 'v1', required_scopes: REQUIRED_READ_SCOPES) do |payload, context|
      handle_list_webhook_deliveries(payload, context)
    end

    # Reports
    @sdk.register('jira.reports.sync_metrics', version: 'v1', required_scopes: REQUIRED_READ_SCOPES) do |payload, context|
      handle_sync_metrics(payload, context)
    end

    @sdk.register('jira.reports.mapping_status', version: 'v1', required_scopes: REQUIRED_READ_SCOPES) do |payload, context|
      handle_mapping_status(payload, context)
    end

    @sdk.register('jira.export.mappings', version: 'v1', required_scopes: REQUIRED_READ_SCOPES) do |payload, context|
      handle_export_mappings(payload, context)
    end
  end

  # Project Handlers

  def handle_register_project(payload, context)
    jira_project_key = payload['jira_project_key']
    kiket_project_id = payload['kiket_project_id']
    jira_url = payload['jira_url']

    unless jira_project_key && kiket_project_id && jira_url
      raise ArgumentError,
            'Missing required fields: jira_project_key, kiket_project_id, jira_url'
    end

    project_id = @projects.length + 1

    @projects[project_id] = {
      id: project_id,
      jira_project_key: jira_project_key,
      jira_project_id: payload['jira_project_id'],
      jira_url: jira_url,
      kiket_project_id: kiket_project_id,
      sync_enabled: payload.fetch('sync_enabled', true),
      sync_direction: payload.fetch('sync_direction', 'bidirectional'),
      sync_comments: payload.fetch('sync_comments', true),
      sync_attachments: payload.fetch('sync_attachments', true),
      sync_labels: payload.fetch('sync_labels', true),
      auto_create_mappings: payload.fetch('auto_create_mappings', false),
      registered_at: Time.now.utc.iso8601,
      last_synced_at: nil,
      org_id: context[:auth][:org_id]
    }

    context[:endpoints].log_event('jira.project.registered', {
                                    jira_project_key: jira_project_key,
                                    org_id: context[:auth][:org_id]
                                  })

    { status: 'registered', project: @projects[project_id] }
  rescue ArgumentError => e
    { success: false, error: e.message }
  end

  def handle_list_projects(payload, context)
    kiket_project_id = payload['kiket_project_id']
    org_id = context[:auth][:org_id]

    projects = @projects.select { |_, p| p[:org_id] == org_id }
    projects = projects.select { |_, p| p[:kiket_project_id] == kiket_project_id } if kiket_project_id

    { projects: projects.values }
  end

  def handle_get_project(payload, _context)
    project_id = payload['id'].to_i
    project = @projects[project_id]

    return { error: 'Project not found' } unless project

    { project: project }
  end

  def handle_delete_project(payload, context)
    project_id = payload['id'].to_i
    project = @projects.delete(project_id)

    return { error: 'Project not found' } unless project

    # Clean up associated data
    @issue_mappings.delete_if { |_, m| m[:project_id] == project_id }
    @field_mappings.delete_if { |_, m| m[:project_id] == project_id }
    @status_mappings.delete_if { |_, m| m[:project_id] == project_id }

    context[:endpoints].log_event('jira.project.deleted', {
                                    jira_project_key: project[:jira_project_key],
                                    org_id: context[:auth][:org_id]
                                  })

    { status: 'deleted' }
  end

  # Issue Mapping Handlers

  def handle_map_issue(payload, context)
    project_id = payload['project_id']
    jira_issue_key = payload['jira_issue_key']
    kiket_issue_id = payload['kiket_issue_id']

    raise ArgumentError, 'Missing required fields: project_id, jira_issue_key, kiket_issue_id' unless project_id && jira_issue_key && kiket_issue_id

    project = @projects[project_id.to_i]
    return { error: 'Project not registered' } unless project

    mapping_id = @issue_mappings.length + 1

    mapping = {
      id: mapping_id,
      project_id: project_id.to_i,
      jira_issue_key: jira_issue_key,
      jira_issue_id: payload['jira_issue_id'],
      kiket_issue_id: kiket_issue_id,
      sync_enabled: payload.fetch('sync_enabled', true),
      last_jira_update: payload['last_jira_update'],
      last_kiket_update: payload['last_kiket_update'],
      last_synced_at: Time.now.utc.iso8601,
      created_at: Time.now.utc.iso8601,
      updated_at: Time.now.utc.iso8601
    }

    @issue_mappings[mapping_id] = mapping

    context[:endpoints].log_event('jira.issue.mapped', {
                                    jira_issue_key: jira_issue_key,
                                    kiket_issue_id: kiket_issue_id,
                                    org_id: context[:auth][:org_id]
                                  })

    { status: 'mapped', mapping: mapping }
  rescue ArgumentError => e
    { success: false, error: e.message }
  end

  def handle_list_issue_mappings(payload, _context)
    project_id = payload['project_id']
    kiket_issue_id = payload['kiket_issue_id']
    jira_issue_key = payload['jira_issue_key']

    mappings = @issue_mappings.values
    mappings = mappings.select { |m| m[:project_id] == project_id.to_i } if project_id
    mappings = mappings.select { |m| m[:kiket_issue_id] == kiket_issue_id } if kiket_issue_id
    mappings = mappings.select { |m| m[:jira_issue_key] == jira_issue_key } if jira_issue_key

    { mappings: mappings }
  end

  def handle_update_issue_mapping(payload, _context)
    mapping_id = payload['id'].to_i
    mapping = @issue_mappings[mapping_id]

    return { error: 'Mapping not found' } unless mapping

    mapping[:sync_enabled] = payload['sync_enabled'] if payload.key?('sync_enabled')
    mapping[:last_jira_update] = payload['last_jira_update'] if payload.key?('last_jira_update')
    mapping[:last_kiket_update] = payload['last_kiket_update'] if payload.key?('last_kiket_update')
    mapping[:updated_at] = Time.now.utc.iso8601

    { status: 'updated', mapping: mapping }
  end

  def handle_delete_issue_mapping(payload, _context)
    mapping_id = payload['id'].to_i
    mapping = @issue_mappings.delete(mapping_id)

    return { error: 'Mapping not found' } unless mapping

    { status: 'deleted' }
  end

  # Field Mapping Handlers

  def handle_map_field(payload, _context)
    project_id = payload['project_id']
    jira_field_id = payload['jira_field_id']
    kiket_field_name = payload['kiket_field_name']

    raise ArgumentError, 'Missing required fields' unless project_id && jira_field_id && kiket_field_name

    project = @projects[project_id.to_i]
    return { error: 'Project not registered' } unless project

    mapping_id = @field_mappings.length + 1

    mapping = {
      id: mapping_id,
      project_id: project_id.to_i,
      jira_field_id: jira_field_id,
      jira_field_name: payload['jira_field_name'],
      kiket_field_name: kiket_field_name,
      field_type: payload['field_type'],
      transform_function: payload['transform_function'],
      sync_direction: payload.fetch('sync_direction', 'bidirectional'),
      created_at: Time.now.utc.iso8601
    }

    @field_mappings[mapping_id] = mapping

    { status: 'mapped', mapping: mapping }
  rescue ArgumentError => e
    { success: false, error: e.message }
  end

  def handle_list_field_mappings(payload, _context)
    project_id = payload['project_id']

    mappings = @field_mappings.values
    mappings = mappings.select { |m| m[:project_id] == project_id.to_i } if project_id

    { mappings: mappings }
  end

  def handle_delete_field_mapping(payload, _context)
    mapping_id = payload['id'].to_i
    mapping = @field_mappings.delete(mapping_id)

    return { error: 'Field mapping not found' } unless mapping

    { status: 'deleted' }
  end

  # Status Mapping Handlers

  def handle_map_status(payload, _context)
    project_id = payload['project_id']
    jira_status_id = payload['jira_status_id']
    kiket_status = payload['kiket_status']

    raise ArgumentError, 'Missing required fields' unless project_id && jira_status_id && kiket_status

    project = @projects[project_id.to_i]
    return { error: 'Project not registered' } unless project

    mapping_id = @status_mappings.length + 1

    mapping = {
      id: mapping_id,
      project_id: project_id.to_i,
      jira_status_id: jira_status_id,
      jira_status_name: payload['jira_status_name'],
      kiket_status: kiket_status,
      sync_on_transition: payload.fetch('sync_on_transition', true),
      created_at: Time.now.utc.iso8601
    }

    @status_mappings[mapping_id] = mapping

    { status: 'mapped', mapping: mapping }
  rescue ArgumentError => e
    { success: false, error: e.message }
  end

  def handle_list_status_mappings(payload, _context)
    project_id = payload['project_id']

    mappings = @status_mappings.values
    mappings = mappings.select { |m| m[:project_id] == project_id.to_i } if project_id

    { mappings: mappings }
  end

  def handle_delete_status_mapping(payload, _context)
    mapping_id = payload['id'].to_i
    mapping = @status_mappings.delete(mapping_id)

    return { error: 'Status mapping not found' } unless mapping

    { status: 'deleted' }
  end

  # Issue Sync Handler

  def handle_sync_issue(payload, context)
    mapping_id = payload['mapping_id']
    direction = payload['direction']

    raise ArgumentError, 'Missing required fields: mapping_id, direction' unless mapping_id && direction

    mapping = @issue_mappings[mapping_id.to_i]
    return { error: 'Issue mapping not found' } unless mapping

    result = {
      mapping_id: mapping_id,
      direction: direction,
      jira_issue_key: mapping[:jira_issue_key],
      kiket_issue_id: mapping[:kiket_issue_id],
      fields_synced: payload.fetch('fields_synced', []),
      comments_synced: payload.fetch('comments_synced', 0),
      attachments_synced: payload.fetch('attachments_synced', 0),
      synced_at: Time.now.utc.iso8601
    }

    mapping[:last_synced_at] = result[:synced_at]

    context[:endpoints].log_event('jira.issue.synced', {
                                    mapping_id: mapping_id,
                                    direction: direction,
                                    org_id: context[:auth][:org_id]
                                  })

    { status: 'synced', result: result }
  rescue ArgumentError => e
    { success: false, error: e.message }
  end

  # Attachment Handlers

  def handle_mirror_attachment(payload, _context)
    mapping_id = payload['mapping_id']
    jira_attachment_id = payload['jira_attachment_id']
    direction = payload['direction']

    raise ArgumentError, 'Missing required fields' unless mapping_id && jira_attachment_id && direction

    mapping = @issue_mappings[mapping_id.to_i]
    return { error: 'Issue mapping not found' } unless mapping

    attachment_id = @attachments.length + 1

    attachment = {
      id: attachment_id,
      mapping_id: mapping_id.to_i,
      jira_attachment_id: jira_attachment_id,
      kiket_attachment_id: payload['kiket_attachment_id'],
      filename: payload['filename'],
      file_size: payload['file_size'],
      mime_type: payload['mime_type'],
      direction: direction,
      mirrored_at: Time.now.utc.iso8601
    }

    @attachments[attachment_id] = attachment

    { status: 'mirrored', attachment: attachment }
  rescue ArgumentError => e
    { success: false, error: e.message }
  end

  def handle_list_attachments(payload, _context)
    mapping_id = payload['mapping_id']

    attachments = @attachments.values
    attachments = attachments.select { |a| a[:mapping_id] == mapping_id.to_i } if mapping_id

    { attachments: attachments }
  end

  # Sync Job Handlers

  def handle_trigger_sync(payload, context)
    project_id = payload['project_id']
    sync_type = payload['sync_type']

    raise ArgumentError, 'Missing required fields: project_id, sync_type' unless project_id && sync_type

    project = @projects[project_id.to_i]
    return { error: 'Project not registered' } unless project
    return { error: 'Sync not enabled' } unless project[:sync_enabled]

    job_id = @sync_jobs.length + 1

    job = {
      id: job_id,
      project_id: project_id.to_i,
      sync_type: sync_type,
      sync_direction: payload.fetch('sync_direction', project[:sync_direction]),
      status: 'queued',
      issues_processed: 0,
      issues_total: nil,
      fields_synced: 0,
      comments_synced: 0,
      attachments_synced: 0,
      errors: [],
      started_at: nil,
      completed_at: nil,
      created_at: Time.now.utc.iso8601
    }

    @sync_jobs << job

    # Simulate job processing start
    job[:status] = 'running'
    job[:started_at] = Time.now.utc.iso8601
    job[:issues_total] = 10

    context[:endpoints].log_event('jira.sync.triggered', {
                                    project_id: project_id,
                                    sync_type: sync_type,
                                    job_id: job_id,
                                    org_id: context[:auth][:org_id]
                                  })

    { status: 'triggered', job: job }
  rescue ArgumentError => e
    { success: false, error: e.message }
  end

  def handle_list_sync_jobs(payload, _context)
    project_id = payload['project_id']
    status_filter = payload['status']
    limit = [payload.fetch('limit', 20).to_i, 100].min

    jobs = @sync_jobs
    jobs = jobs.select { |j| j[:project_id] == project_id.to_i } if project_id
    jobs = jobs.select { |j| j[:status] == status_filter } if status_filter
    jobs = jobs.reverse.take(limit)

    { jobs: jobs }
  end

  def handle_get_sync_job(payload, _context)
    job_id = payload['id'].to_i
    job = @sync_jobs.find { |j| j[:id] == job_id }

    return { error: 'Job not found' } unless job

    { job: job }
  end

  # Webhook Handlers

  def handle_jira_webhook(payload, context)
    raw_payload = payload['raw_payload']
    event_type = payload['event_type']

    data = raw_payload.is_a?(String) ? JSON.parse(raw_payload) : raw_payload

    delivery = {
      id: @webhook_deliveries.length + 1,
      event_type: event_type,
      webhook_event: data['webhookEvent'],
      issue_key: data.dig('issue', 'key'),
      received_at: Time.now.utc.iso8601,
      processed: false,
      error: nil
    }

    begin
      case data['webhookEvent']
      when 'jira:issue_created'
        handle_issue_created(data)
      when 'jira:issue_updated'
        handle_issue_updated(data)
      when 'jira:issue_deleted'
        handle_issue_deleted(data)
      when 'comment_created', 'comment_updated'
        handle_comment_event(data)
      else
        delivery[:error] = "Unsupported event type: #{data['webhookEvent']}"
      end

      delivery[:processed] = true
    rescue StandardError => e
      delivery[:error] = e.message
      delivery[:processed] = false
    end

    @webhook_deliveries << delivery

    context[:endpoints].log_event('jira.webhook.received', {
                                    webhook_event: data['webhookEvent'],
                                    issue_key: data.dig('issue', 'key'),
                                    org_id: context[:auth][:org_id]
                                  })

    { status: 'received', delivery_id: delivery[:id] }
  end

  def handle_kiket_issue_transitioned(payload, _context)
    issue_id = payload['issue_id']
    to_status = payload['to_status']

    mapping = @issue_mappings.values.find { |m| m[:kiket_issue_id] == issue_id }
    return { status: 'no_mapping' } unless mapping

    status_map = @status_mappings.values.find do |sm|
      sm[:project_id] == mapping[:project_id] && sm[:kiket_status] == to_status
    end

    result = {
      mapping_id: mapping[:id],
      jira_issue_key: mapping[:jira_issue_key],
      kiket_status: to_status,
      jira_status: status_map&.[](:jira_status_name),
      synced: !status_map.nil?
    }

    { status: 'processed', result: result }
  end

  def handle_list_webhook_deliveries(payload, _context)
    limit = [payload.fetch('limit', 50).to_i, 100].min
    offset = payload.fetch('offset', 0).to_i

    deliveries = @webhook_deliveries.reverse[offset, limit] || []

    {
      deliveries: deliveries,
      total: @webhook_deliveries.length,
      limit: limit,
      offset: offset
    }
  end

  # Report Handlers

  def handle_sync_metrics(payload, _context)
    project_id = payload['project_id']

    jobs = @sync_jobs
    jobs = jobs.select { |j| j[:project_id] == project_id.to_i } if project_id

    total_jobs = jobs.length
    successful_jobs = jobs.count { |j| j[:status] == 'completed' }
    failed_jobs = jobs.count { |j| j[:status] == 'failed' }
    running_jobs = jobs.count { |j| j[:status] == 'running' }

    total_issues = jobs.sum { |j| j[:issues_processed] }
    total_comments = jobs.sum { |j| j[:comments_synced] }
    total_attachments = jobs.sum { |j| j[:attachments_synced] }

    {
      total_jobs: total_jobs,
      successful_jobs: successful_jobs,
      failed_jobs: failed_jobs,
      running_jobs: running_jobs,
      success_rate: total_jobs.zero? ? 0 : (successful_jobs.to_f / total_jobs * 100).round(2),
      total_issues_synced: total_issues,
      total_comments_synced: total_comments,
      total_attachments_synced: total_attachments,
      active_mappings: @issue_mappings.values.count { |m| m[:sync_enabled] }
    }
  end

  def handle_mapping_status(payload, _context)
    project_id = payload['project_id']

    mappings = @issue_mappings.values
    mappings = mappings.select { |m| m[:project_id] == project_id.to_i } if project_id

    total_mappings = mappings.length
    enabled_mappings = mappings.count { |m| m[:sync_enabled] }
    recently_synced = mappings.count { |m| m[:last_synced_at] && Time.parse(m[:last_synced_at]) > Time.now - 86_400 }

    {
      total_mappings: total_mappings,
      enabled_mappings: enabled_mappings,
      disabled_mappings: total_mappings - enabled_mappings,
      recently_synced_24h: recently_synced,
      projects: @projects.length
    }
  end

  def handle_export_mappings(payload, _context)
    project_id = payload['project_id']

    mappings = @issue_mappings.values
    mappings = mappings.select { |m| m[:project_id] == project_id.to_i } if project_id

    csv = "ID,Project ID,Jira Issue Key,Jira Issue ID,Kiket Issue ID,Sync Enabled,Last Synced At,Created At\n"

    mappings.each do |m|
      csv += [
        m[:id],
        m[:project_id],
        m[:jira_issue_key],
        m[:jira_issue_id],
        m[:kiket_issue_id],
        m[:sync_enabled],
        m[:last_synced_at],
        m[:created_at]
      ].map { |v| "\"#{v}\"" }.join(',') + "\n"
    end

    { format: 'csv', content: csv, filename: 'jira_mappings.csv' }
  end

  # Private webhook event handlers

  def handle_issue_created(data)
    issue = data['issue']
    project_key = issue['fields']['project']['key']

    project = @projects.values.find { |p| p[:jira_project_key] == project_key }
    nil unless project && project[:auto_create_mappings]

    # Would create Kiket issue and mapping here
  end

  def handle_issue_updated(data)
    issue = data['issue']
    issue_key = issue['key']

    mapping = @issue_mappings.values.find { |m| m[:jira_issue_key] == issue_key }
    return unless mapping && mapping[:sync_enabled]

    mapping[:last_jira_update] = data['timestamp']
    # Would sync changes to Kiket here
  end

  def handle_issue_deleted(data)
    issue = data['issue']
    issue_key = issue['key']

    mapping = @issue_mappings.values.find { |m| m[:jira_issue_key] == issue_key }
    nil unless mapping

    # Would handle deletion sync based on project settings
  end

  def handle_comment_event(data)
    issue = data['issue']
    issue_key = issue['key']

    mapping = @issue_mappings.values.find { |m| m[:jira_issue_key] == issue_key }
    return unless mapping

    project = @projects[mapping[:project_id]]
    nil unless project && project[:sync_comments]

    # Would sync comment to Kiket here
  end
end

# Run the extension
if __FILE__ == $PROGRAM_NAME
  extension = JiraExtension.new

  Rackup::Handler.get(:puma).run(
    extension.app,
    Host: ENV.fetch('HOST', '0.0.0.0'),
    Port: ENV.fetch('PORT', 8080).to_i,
    Threads: '0:16'
  )
end
