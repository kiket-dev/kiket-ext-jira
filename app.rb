# frozen_string_literal: true

require "sinatra/base"
require "json"
require "faraday"
require "faraday/multipart"
require "base64"

class JiraExtension < Sinatra::Base
  configure do
    set :show_exceptions, false
    set :raise_errors, false
  end

  # Store for Jira data (in production, this would use custom_data tables)
  configure do
    set :projects, {}
    set :issue_mappings, {}
    set :field_mappings, {}
    set :status_mappings, {}
    set :sync_jobs, []
    set :webhook_deliveries, []
    set :attachments, {}
  end

  # Health check
  get "/health" do
    content_type :json
    { status: "ok", extension: "jira", version: "1.0.0" }.to_json
  end

  # Project Management

  post "/projects/register" do
    data = JSON.parse(request.body.read)

    jira_project_key = data["jira_project_key"]
    kiket_project_id = data["kiket_project_id"]
    jira_url = data["jira_url"]

    halt 400, { error: "Missing required fields" }.to_json unless jira_project_key && kiket_project_id && jira_url

    project_id = settings.projects.length + 1

    settings.projects[project_id] = {
      id: project_id,
      jira_project_key: jira_project_key,
      jira_project_id: data["jira_project_id"],
      jira_url: jira_url,
      kiket_project_id: kiket_project_id,
      sync_enabled: data.fetch("sync_enabled", true),
      sync_direction: data.fetch("sync_direction", "bidirectional"),
      sync_comments: data.fetch("sync_comments", true),
      sync_attachments: data.fetch("sync_attachments", true),
      sync_labels: data.fetch("sync_labels", true),
      auto_create_mappings: data.fetch("auto_create_mappings", false),
      registered_at: Time.now.utc.iso8601,
      last_synced_at: nil
    }

    content_type :json
    status 201
    { status: "registered", project: settings.projects[project_id] }.to_json
  end

  get "/projects" do
    kiket_project_id = params["kiket_project_id"]

    projects = if kiket_project_id
      settings.projects.select { |_, p| p[:kiket_project_id] == kiket_project_id }
    else
      settings.projects
    end

    content_type :json
    { projects: projects.values }.to_json
  end

  get "/projects/:id" do
    project_id = params[:id].to_i
    project = settings.projects[project_id]

    halt 404, { error: "Project not found" }.to_json unless project

    content_type :json
    { project: project }.to_json
  end

  delete "/projects/:id" do
    project_id = params[:id].to_i
    project = settings.projects.delete(project_id)

    halt 404, { error: "Project not found" }.to_json unless project

    # Clean up associated data
    settings.issue_mappings.delete_if { |_, m| m[:project_id] == project_id }
    settings.field_mappings.delete_if { |_, m| m[:project_id] == project_id }
    settings.status_mappings.delete_if { |_, m| m[:project_id] == project_id }

    content_type :json
    { status: "deleted" }.to_json
  end

  # Issue Mapping

  post "/issues/map" do
    data = JSON.parse(request.body.read)

    project_id = data["project_id"]
    jira_issue_key = data["jira_issue_key"]
    kiket_issue_id = data["kiket_issue_id"]

    halt 400, { error: "Missing required fields" }.to_json unless project_id && jira_issue_key && kiket_issue_id

    project = settings.projects[project_id.to_i]
    halt 404, { error: "Project not registered" }.to_json unless project

    mapping_id = settings.issue_mappings.length + 1

    mapping = {
      id: mapping_id,
      project_id: project_id.to_i,
      jira_issue_key: jira_issue_key,
      jira_issue_id: data["jira_issue_id"],
      kiket_issue_id: kiket_issue_id,
      sync_enabled: data.fetch("sync_enabled", true),
      last_jira_update: data["last_jira_update"],
      last_kiket_update: data["last_kiket_update"],
      last_synced_at: Time.now.utc.iso8601,
      created_at: Time.now.utc.iso8601,
      updated_at: Time.now.utc.iso8601
    }

    settings.issue_mappings[mapping_id] = mapping

    content_type :json
    status 201
    { status: "mapped", mapping: mapping }.to_json
  end

  get "/issues/mappings" do
    project_id = params["project_id"]
    kiket_issue_id = params["kiket_issue_id"]
    jira_issue_key = params["jira_issue_key"]

    mappings = settings.issue_mappings.values
    mappings = mappings.select { |m| m[:project_id] == project_id.to_i } if project_id
    mappings = mappings.select { |m| m[:kiket_issue_id] == kiket_issue_id } if kiket_issue_id
    mappings = mappings.select { |m| m[:jira_issue_key] == jira_issue_key } if jira_issue_key

    content_type :json
    { mappings: mappings }.to_json
  end

  put "/issues/mappings/:id" do
    mapping_id = params[:id].to_i
    mapping = settings.issue_mappings[mapping_id]

    halt 404, { error: "Mapping not found" }.to_json unless mapping

    data = JSON.parse(request.body.read)

    mapping[:sync_enabled] = data["sync_enabled"] if data.key?("sync_enabled")
    mapping[:last_jira_update] = data["last_jira_update"] if data.key?("last_jira_update")
    mapping[:last_kiket_update] = data["last_kiket_update"] if data.key?("last_kiket_update")
    mapping[:updated_at] = Time.now.utc.iso8601

    content_type :json
    { status: "updated", mapping: mapping }.to_json
  end

  delete "/issues/mappings/:id" do
    mapping_id = params[:id].to_i
    mapping = settings.issue_mappings.delete(mapping_id)

    halt 404, { error: "Mapping not found" }.to_json unless mapping

    content_type :json
    { status: "deleted" }.to_json
  end

  # Field Mapping

  post "/fields/map" do
    data = JSON.parse(request.body.read)

    project_id = data["project_id"]
    jira_field_id = data["jira_field_id"]
    kiket_field_name = data["kiket_field_name"]

    halt 400, { error: "Missing required fields" }.to_json unless project_id && jira_field_id && kiket_field_name

    project = settings.projects[project_id.to_i]
    halt 404, { error: "Project not registered" }.to_json unless project

    mapping_id = settings.field_mappings.length + 1

    mapping = {
      id: mapping_id,
      project_id: project_id.to_i,
      jira_field_id: jira_field_id,
      jira_field_name: data["jira_field_name"],
      kiket_field_name: kiket_field_name,
      field_type: data["field_type"],
      transform_function: data["transform_function"],
      sync_direction: data.fetch("sync_direction", "bidirectional"),
      created_at: Time.now.utc.iso8601
    }

    settings.field_mappings[mapping_id] = mapping

    content_type :json
    status 201
    { status: "mapped", mapping: mapping }.to_json
  end

  get "/fields/mappings" do
    project_id = params["project_id"]

    mappings = settings.field_mappings.values
    mappings = mappings.select { |m| m[:project_id] == project_id.to_i } if project_id

    content_type :json
    { mappings: mappings }.to_json
  end

  delete "/fields/mappings/:id" do
    mapping_id = params[:id].to_i
    mapping = settings.field_mappings.delete(mapping_id)

    halt 404, { error: "Field mapping not found" }.to_json unless mapping

    content_type :json
    { status: "deleted" }.to_json
  end

  # Status Mapping

  post "/status/map" do
    data = JSON.parse(request.body.read)

    project_id = data["project_id"]
    jira_status_id = data["jira_status_id"]
    kiket_status = data["kiket_status"]

    halt 400, { error: "Missing required fields" }.to_json unless project_id && jira_status_id && kiket_status

    project = settings.projects[project_id.to_i]
    halt 404, { error: "Project not registered" }.to_json unless project

    mapping_id = settings.status_mappings.length + 1

    mapping = {
      id: mapping_id,
      project_id: project_id.to_i,
      jira_status_id: jira_status_id,
      jira_status_name: data["jira_status_name"],
      kiket_status: kiket_status,
      sync_on_transition: data.fetch("sync_on_transition", true),
      created_at: Time.now.utc.iso8601
    }

    settings.status_mappings[mapping_id] = mapping

    content_type :json
    status 201
    { status: "mapped", mapping: mapping }.to_json
  end

  get "/status/mappings" do
    project_id = params["project_id"]

    mappings = settings.status_mappings.values
    mappings = mappings.select { |m| m[:project_id] == project_id.to_i } if project_id

    content_type :json
    { mappings: mappings }.to_json
  end

  delete "/status/mappings/:id" do
    mapping_id = params[:id].to_i
    mapping = settings.status_mappings.delete(mapping_id)

    halt 404, { error: "Status mapping not found" }.to_json unless mapping

    content_type :json
    { status: "deleted" }.to_json
  end

  # Issue Synchronization

  post "/sync/issue" do
    data = JSON.parse(request.body.read)

    mapping_id = data["mapping_id"]
    direction = data["direction"] # 'jira_to_kiket', 'kiket_to_jira', 'bidirectional'

    halt 400, { error: "Missing required fields" }.to_json unless mapping_id && direction

    mapping = settings.issue_mappings[mapping_id.to_i]
    halt 404, { error: "Issue mapping not found" }.to_json unless mapping

    # In production, this would make actual API calls to Jira and Kiket
    result = {
      mapping_id: mapping_id,
      direction: direction,
      jira_issue_key: mapping[:jira_issue_key],
      kiket_issue_id: mapping[:kiket_issue_id],
      fields_synced: data.fetch("fields_synced", []),
      comments_synced: data.fetch("comments_synced", 0),
      attachments_synced: data.fetch("attachments_synced", 0),
      synced_at: Time.now.utc.iso8601
    }

    mapping[:last_synced_at] = result[:synced_at]

    content_type :json
    { status: "synced", result: result }.to_json
  end

  # Attachment Management

  post "/attachments/mirror" do
    data = JSON.parse(request.body.read)

    mapping_id = data["mapping_id"]
    jira_attachment_id = data["jira_attachment_id"]
    direction = data["direction"] # 'jira_to_kiket' or 'kiket_to_jira'

    halt 400, { error: "Missing required fields" }.to_json unless mapping_id && jira_attachment_id && direction

    mapping = settings.issue_mappings[mapping_id.to_i]
    halt 404, { error: "Issue mapping not found" }.to_json unless mapping

    attachment_id = settings.attachments.length + 1

    attachment = {
      id: attachment_id,
      mapping_id: mapping_id.to_i,
      jira_attachment_id: jira_attachment_id,
      kiket_attachment_id: data["kiket_attachment_id"],
      filename: data["filename"],
      file_size: data["file_size"],
      mime_type: data["mime_type"],
      direction: direction,
      mirrored_at: Time.now.utc.iso8601
    }

    settings.attachments[attachment_id] = attachment

    content_type :json
    status 201
    { status: "mirrored", attachment: attachment }.to_json
  end

  get "/attachments" do
    mapping_id = params["mapping_id"]

    attachments = settings.attachments.values
    attachments = attachments.select { |a| a[:mapping_id] == mapping_id.to_i } if mapping_id

    content_type :json
    { attachments: attachments }.to_json
  end

  # Sync Jobs

  post "/sync/trigger" do
    data = JSON.parse(request.body.read)

    project_id = data["project_id"]
    sync_type = data["sync_type"] # 'full', 'incremental', 'issues_only', 'mappings_only'

    halt 400, { error: "Missing required fields" }.to_json unless project_id && sync_type

    project = settings.projects[project_id.to_i]
    halt 404, { error: "Project not registered" }.to_json unless project
    halt 400, { error: "Sync not enabled" }.to_json unless project[:sync_enabled]

    job_id = settings.sync_jobs.length + 1

    job = {
      id: job_id,
      project_id: project_id.to_i,
      sync_type: sync_type,
      sync_direction: data.fetch("sync_direction", project[:sync_direction]),
      status: "queued",
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

    settings.sync_jobs << job

    # Simulate job processing
    job[:status] = "running"
    job[:started_at] = Time.now.utc.iso8601
    job[:issues_total] = 10

    content_type :json
    status 202
    { status: "triggered", job: job }.to_json
  end

  get "/sync/jobs" do
    project_id = params["project_id"]
    status_filter = params["status"]
    limit = [ params.fetch("limit", "20").to_i, 100 ].min

    jobs = settings.sync_jobs
    jobs = jobs.select { |j| j[:project_id] == project_id.to_i } if project_id
    jobs = jobs.select { |j| j[:status] == status_filter } if status_filter
    jobs = jobs.reverse.take(limit)

    content_type :json
    { jobs: jobs }.to_json
  end

  get "/sync/jobs/:id" do
    job_id = params[:id].to_i
    job = settings.sync_jobs.find { |j| j[:id] == job_id }

    halt 404, { error: "Job not found" }.to_json unless job

    content_type :json
    { job: job }.to_json
  end

  # Webhooks

  post "/webhooks/jira" do
    payload = request.body.read
    event_type = request.env["HTTP_X_ATLASSIAN_WEBHOOK_IDENTIFIER"]

    data = JSON.parse(payload)

    delivery = {
      id: settings.webhook_deliveries.length + 1,
      event_type: event_type,
      webhook_event: data["webhookEvent"],
      issue_key: data.dig("issue", "key"),
      received_at: Time.now.utc.iso8601,
      processed: false,
      error: nil
    }

    begin
      case data["webhookEvent"]
      when "jira:issue_created"
        handle_issue_created(data)
      when "jira:issue_updated"
        handle_issue_updated(data)
      when "jira:issue_deleted"
        handle_issue_deleted(data)
      when "comment_created", "comment_updated"
        handle_comment_event(data)
      else
        delivery[:error] = "Unsupported event type: #{data["webhookEvent"]}"
      end

      delivery[:processed] = true
    rescue StandardError => e
      delivery[:error] = e.message
      delivery[:processed] = false
    end

    settings.webhook_deliveries << delivery

    content_type :json
    { status: "received", delivery_id: delivery[:id] }.to_json
  end

  post "/webhooks/kiket/issue_transitioned" do
    data = JSON.parse(request.body.read)

    issue_id = data["issue_id"]
    to_status = data["to_status"]

    # Find mapping
    mapping = settings.issue_mappings.values.find { |m| m[:kiket_issue_id] == issue_id }

    return { status: "no_mapping" }.to_json unless mapping

    # Find status mapping
    status_map = settings.status_mappings.values.find do |sm|
      sm[:project_id] == mapping[:project_id] && sm[:kiket_status] == to_status
    end

    result = {
      mapping_id: mapping[:id],
      jira_issue_key: mapping[:jira_issue_key],
      kiket_status: to_status,
      jira_status: status_map&.[](:jira_status_name),
      synced: !status_map.nil?
    }

    content_type :json
    { status: "processed", result: result }.to_json
  end

  get "/webhooks/deliveries" do
    limit = [ params.fetch("limit", "50").to_i, 100 ].min
    offset = params.fetch("offset", "0").to_i

    deliveries = settings.webhook_deliveries.reverse[offset, limit] || []

    content_type :json
    {
      deliveries: deliveries,
      total: settings.webhook_deliveries.length,
      limit: limit,
      offset: offset
    }.to_json
  end

  # Reports

  get "/reports/sync_metrics" do
    project_id = params["project_id"]

    jobs = settings.sync_jobs
    jobs = jobs.select { |j| j[:project_id] == project_id.to_i } if project_id

    total_jobs = jobs.length
    successful_jobs = jobs.count { |j| j[:status] == "completed" }
    failed_jobs = jobs.count { |j| j[:status] == "failed" }
    running_jobs = jobs.count { |j| j[:status] == "running" }

    total_issues = jobs.sum { |j| j[:issues_processed] }
    total_comments = jobs.sum { |j| j[:comments_synced] }
    total_attachments = jobs.sum { |j| j[:attachments_synced] }

    content_type :json
    {
      total_jobs: total_jobs,
      successful_jobs: successful_jobs,
      failed_jobs: failed_jobs,
      running_jobs: running_jobs,
      success_rate: total_jobs.zero? ? 0 : (successful_jobs.to_f / total_jobs * 100).round(2),
      total_issues_synced: total_issues,
      total_comments_synced: total_comments,
      total_attachments_synced: total_attachments,
      active_mappings: settings.issue_mappings.values.count { |m| m[:sync_enabled] }
    }.to_json
  end

  get "/reports/mapping_status" do
    project_id = params["project_id"]

    mappings = settings.issue_mappings.values
    mappings = mappings.select { |m| m[:project_id] == project_id.to_i } if project_id

    total_mappings = mappings.length
    enabled_mappings = mappings.count { |m| m[:sync_enabled] }
    recently_synced = mappings.count { |m| m[:last_synced_at] && Time.parse(m[:last_synced_at]) > Time.now - 86400 }

    content_type :json
    {
      total_mappings: total_mappings,
      enabled_mappings: enabled_mappings,
      disabled_mappings: total_mappings - enabled_mappings,
      recently_synced_24h: recently_synced,
      projects: settings.projects.length
    }.to_json
  end

  # Export

  get "/export/mappings/csv" do
    project_id = params["project_id"]

    mappings = settings.issue_mappings.values
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
      ].map { |v| "\"#{v}\"" }.join(",") + "\n"
    end

    content_type "text/csv"
    attachment "jira_mappings.csv"
    csv
  end

  # Error handling
  error 400 do
    content_type :json
    { error: "Bad request" }.to_json
  end

  error 404 do
    content_type :json
    { error: "Not found" }.to_json
  end

  error 500 do
    content_type :json
    { error: "Internal server error" }.to_json
  end

  private

  def handle_issue_created(data)
    issue = data["issue"]
    project_key = issue["fields"]["project"]["key"]

    # Find project mapping
    project = settings.projects.values.find { |p| p[:jira_project_key] == project_key }
    nil unless project && project[:auto_create_mappings]

    # Would create Kiket issue and mapping here
  end

  def handle_issue_updated(data)
    issue = data["issue"]
    issue_key = issue["key"]

    # Find mapping
    mapping = settings.issue_mappings.values.find { |m| m[:jira_issue_key] == issue_key }
    return unless mapping && mapping[:sync_enabled]

    # Update last_jira_update timestamp
    mapping[:last_jira_update] = data["timestamp"]

    # Would sync changes to Kiket here
  end

  def handle_issue_deleted(data)
    issue = data["issue"]
    issue_key = issue["key"]

    # Find mapping
    mapping = settings.issue_mappings.values.find { |m| m[:jira_issue_key] == issue_key }
    nil unless mapping

    # Would handle deletion sync based on project settings
  end

  def handle_comment_event(data)
    issue = data["issue"]
    comment = data["comment"]
    issue_key = issue["key"]

    # Find mapping
    mapping = settings.issue_mappings.values.find { |m| m[:jira_issue_key] == issue_key }
    return unless mapping

    project = settings.projects[mapping[:project_id]]
    nil unless project && project[:sync_comments]

    # Would sync comment to Kiket here
  end
end
