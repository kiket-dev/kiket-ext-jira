# frozen_string_literal: true

require "spec_helper"

RSpec.describe JiraExtension do
  describe "GET /health" do
    it "returns health status" do
      get "/health"

      expect(last_response).to be_ok
      body = JSON.parse(last_response.body)
      expect(body["status"]).to eq("ok")
      expect(body["extension"]).to eq("jira")
    end
  end

  describe "POST /projects/register" do
    it "registers a new Jira project" do
      post "/projects/register", JSON.generate({
        jira_project_key: "PROJ",
        kiket_project_id: "proj-123",
        jira_url: "https://company.atlassian.net"
      }), "CONTENT_TYPE" => "application/json"

      expect(last_response.status).to eq(201)
      body = JSON.parse(last_response.body)
      expect(body["status"]).to eq("registered")
      expect(body["project"]["jira_project_key"]).to eq("PROJ")
    end

    it "requires required fields" do
      post "/projects/register", JSON.generate({
        kiket_project_id: "proj-123"
      }), "CONTENT_TYPE" => "application/json"

      expect(last_response.status).to eq(400)
    end
  end

  describe "POST /issues/map" do
    before do
      post "/projects/register", JSON.generate({
        jira_project_key: "PROJ",
        kiket_project_id: "proj-123",
        jira_url: "https://company.atlassian.net"
      }), "CONTENT_TYPE" => "application/json"
    end

    it "creates an issue mapping" do
      post "/issues/map", JSON.generate({
        project_id: 1,
        jira_issue_key: "PROJ-123",
        kiket_issue_id: "ISSUE-456"
      }), "CONTENT_TYPE" => "application/json"

      expect(last_response.status).to eq(201)
      body = JSON.parse(last_response.body)
      expect(body["status"]).to eq("mapped")
      expect(body["mapping"]["jira_issue_key"]).to eq("PROJ-123")
    end
  end

  describe "POST /fields/map" do
    before do
      post "/projects/register", JSON.generate({
        jira_project_key: "PROJ",
        kiket_project_id: "proj-123",
        jira_url: "https://company.atlassian.net"
      }), "CONTENT_TYPE" => "application/json"
    end

    it "creates a field mapping" do
      post "/fields/map", JSON.generate({
        project_id: 1,
        jira_field_id: "customfield_10001",
        jira_field_name: "Story Points",
        kiket_field_name: "effort"
      }), "CONTENT_TYPE" => "application/json"

      expect(last_response.status).to eq(201)
      body = JSON.parse(last_response.body)
      expect(body["status"]).to eq("mapped")
      expect(body["mapping"]["jira_field_id"]).to eq("customfield_10001")
    end
  end

  describe "POST /status/map" do
    before do
      post "/projects/register", JSON.generate({
        jira_project_key: "PROJ",
        kiket_project_id: "proj-123",
        jira_url: "https://company.atlassian.net"
      }), "CONTENT_TYPE" => "application/json"
    end

    it "creates a status mapping" do
      post "/status/map", JSON.generate({
        project_id: 1,
        jira_status_id: "10001",
        jira_status_name: "In Progress",
        kiket_status: "in_progress"
      }), "CONTENT_TYPE" => "application/json"

      expect(last_response.status).to eq(201)
      body = JSON.parse(last_response.body)
      expect(body["status"]).to eq("mapped")
      expect(body["mapping"]["jira_status_name"]).to eq("In Progress")
    end
  end

  describe "POST /sync/issue" do
    before do
      post "/projects/register", JSON.generate({
        jira_project_key: "PROJ",
        kiket_project_id: "proj-123",
        jira_url: "https://company.atlassian.net"
      }), "CONTENT_TYPE" => "application/json"

      post "/issues/map", JSON.generate({
        project_id: 1,
        jira_issue_key: "PROJ-123",
        kiket_issue_id: "ISSUE-456"
      }), "CONTENT_TYPE" => "application/json"
    end

    it "syncs an issue" do
      post "/sync/issue", JSON.generate({
        mapping_id: 1,
        direction: "bidirectional"
      }), "CONTENT_TYPE" => "application/json"

      expect(last_response).to be_ok
      body = JSON.parse(last_response.body)
      expect(body["status"]).to eq("synced")
      expect(body["result"]["direction"]).to eq("bidirectional")
    end
  end

  describe "POST /attachments/mirror" do
    before do
      post "/projects/register", JSON.generate({
        jira_project_key: "PROJ",
        kiket_project_id: "proj-123",
        jira_url: "https://company.atlassian.net"
      }), "CONTENT_TYPE" => "application/json"

      post "/issues/map", JSON.generate({
        project_id: 1,
        jira_issue_key: "PROJ-123",
        kiket_issue_id: "ISSUE-456"
      }), "CONTENT_TYPE" => "application/json"
    end

    it "mirrors an attachment" do
      post "/attachments/mirror", JSON.generate({
        mapping_id: 1,
        jira_attachment_id: "12345",
        filename: "document.pdf",
        direction: "jira_to_kiket"
      }), "CONTENT_TYPE" => "application/json"

      expect(last_response.status).to eq(201)
      body = JSON.parse(last_response.body)
      expect(body["status"]).to eq("mirrored")
      expect(body["attachment"]["filename"]).to eq("document.pdf")
    end
  end

  describe "POST /sync/trigger" do
    before do
      post "/projects/register", JSON.generate({
        jira_project_key: "PROJ",
        kiket_project_id: "proj-123",
        jira_url: "https://company.atlassian.net"
      }), "CONTENT_TYPE" => "application/json"
    end

    it "triggers a sync job" do
      post "/sync/trigger", JSON.generate({
        project_id: 1,
        sync_type: "full"
      }), "CONTENT_TYPE" => "application/json"

      expect(last_response.status).to eq(202)
      body = JSON.parse(last_response.body)
      expect(body["status"]).to eq("triggered")
      expect(body["job"]["sync_type"]).to eq("full")
    end
  end

  describe "POST /webhooks/jira" do
    it "handles Jira webhook" do
      payload = {
        webhookEvent: "jira:issue_created",
        issue: {
          key: "PROJ-123",
          fields: {
            project: { key: "PROJ" }
          }
        }
      }

      post "/webhooks/jira", JSON.generate(payload),
        "CONTENT_TYPE" => "application/json",
        "HTTP_X_ATLASSIAN_WEBHOOK_IDENTIFIER" => "test-webhook"

      expect(last_response).to be_ok
      body = JSON.parse(last_response.body)
      expect(body["status"]).to eq("received")
    end
  end

  describe "GET /reports/sync_metrics" do
    before do
      post "/projects/register", JSON.generate({
        jira_project_key: "PROJ",
        kiket_project_id: "proj-123",
        jira_url: "https://company.atlassian.net"
      }), "CONTENT_TYPE" => "application/json"
    end

    it "returns sync metrics" do
      get "/reports/sync_metrics?project_id=1"

      expect(last_response).to be_ok
      body = JSON.parse(last_response.body)
      expect(body).to have_key("total_jobs")
      expect(body).to have_key("success_rate")
    end
  end

  describe "GET /export/mappings/csv" do
    before do
      post "/projects/register", JSON.generate({
        jira_project_key: "PROJ",
        kiket_project_id: "proj-123",
        jira_url: "https://company.atlassian.net"
      }), "CONTENT_TYPE" => "application/json"

      post "/issues/map", JSON.generate({
        project_id: 1,
        jira_issue_key: "PROJ-123",
        kiket_issue_id: "ISSUE-456"
      }), "CONTENT_TYPE" => "application/json"
    end

    it "exports mappings as CSV" do
      get "/export/mappings/csv"

      expect(last_response).to be_ok
      expect(last_response.content_type).to include("text/csv")
      expect(last_response.body).to include("PROJ-123")
    end
  end
end
