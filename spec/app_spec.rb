# frozen_string_literal: true

require "spec_helper"

RSpec.describe JiraExtension do
  subject(:extension) { described_class.new }

  let(:context) { build_context }

  describe "#handle_register_project" do
    let(:payload) do
      {
        "jira_project_key" => "PROJ",
        "kiket_project_id" => "kiket-123",
        "sync_direction" => "bidirectional"
      }
    end

    it "registers a new project" do
      result = extension.send(:handle_register_project, payload, context)

      expect(result[:status]).to eq("registered")
      expect(result[:project][:jira_project_key]).to eq("PROJ")
      expect(result[:project][:kiket_project_id]).to eq("kiket-123")
    end

    it "requires jira_project_key and kiket_project_id" do
      result = extension.send(:handle_register_project, {}, context)

      expect(result[:error]).to be_present
    end
  end

  describe "#handle_list_projects" do
    before do
      extension.send(:handle_register_project, {
        "jira_project_key" => "PROJ",
        "kiket_project_id" => "kiket-123"
      }, context)
    end

    it "lists all projects" do
      result = extension.send(:handle_list_projects, {}, context)

      expect(result[:projects]).to be_an(Array)
      expect(result[:projects].length).to eq(1)
    end
  end

  describe "#handle_delete_project" do
    before do
      extension.send(:handle_register_project, {
        "jira_project_key" => "PROJ",
        "kiket_project_id" => "kiket-123"
      }, context)
    end

    it "deletes a project" do
      result = extension.send(:handle_delete_project, {
        "jira_project_key" => "PROJ"
      }, context)

      expect(result[:status]).to eq("deleted")

      list_result = extension.send(:handle_list_projects, {}, context)
      expect(list_result[:projects].length).to eq(0)
    end
  end

  describe "#handle_create_mapping" do
    before do
      extension.send(:handle_register_project, {
        "jira_project_key" => "PROJ",
        "kiket_project_id" => "kiket-123"
      }, context)
    end

    it "creates an issue mapping" do
      result = extension.send(:handle_create_mapping, {
        "jira_project_key" => "PROJ",
        "jira_issue_key" => "PROJ-1",
        "kiket_issue_id" => "ISSUE-123",
        "direction" => "jira_to_kiket"
      }, context)

      expect(result[:status]).to eq("created")
      expect(result[:mapping][:jira_issue_key]).to eq("PROJ-1")
      expect(result[:mapping][:kiket_issue_id]).to eq("ISSUE-123")
    end
  end

  describe "#handle_list_mappings" do
    before do
      extension.send(:handle_register_project, {
        "jira_project_key" => "PROJ",
        "kiket_project_id" => "kiket-123"
      }, context)

      extension.send(:handle_create_mapping, {
        "jira_project_key" => "PROJ",
        "jira_issue_key" => "PROJ-1",
        "kiket_issue_id" => "ISSUE-123"
      }, context)
    end

    it "lists all mappings" do
      result = extension.send(:handle_list_mappings, {}, context)

      expect(result[:mappings]).to be_an(Array)
      expect(result[:mappings].length).to eq(1)
    end

    it "filters by project" do
      result = extension.send(:handle_list_mappings, {
        "jira_project_key" => "PROJ"
      }, context)

      expect(result[:mappings].length).to eq(1)
    end
  end

  describe "#handle_set_field_mapping" do
    before do
      extension.send(:handle_register_project, {
        "jira_project_key" => "PROJ",
        "kiket_project_id" => "kiket-123"
      }, context)
    end

    it "creates a field mapping" do
      result = extension.send(:handle_set_field_mapping, {
        "jira_project_key" => "PROJ",
        "jira_field" => "customfield_10001",
        "kiket_field" => "story_points",
        "transform" => "integer"
      }, context)

      expect(result[:status]).to eq("set")
      expect(result[:field_mapping][:jira_field]).to eq("customfield_10001")
      expect(result[:field_mapping][:kiket_field]).to eq("story_points")
    end
  end

  describe "#handle_set_status_mapping" do
    before do
      extension.send(:handle_register_project, {
        "jira_project_key" => "PROJ",
        "kiket_project_id" => "kiket-123"
      }, context)
    end

    it "creates a status mapping" do
      result = extension.send(:handle_set_status_mapping, {
        "jira_project_key" => "PROJ",
        "jira_status" => "In Progress",
        "kiket_status" => "in_progress"
      }, context)

      expect(result[:status]).to eq("set")
      expect(result[:status_mapping][:jira_status]).to eq("In Progress")
      expect(result[:status_mapping][:kiket_status]).to eq("in_progress")
    end
  end

  describe "#handle_trigger_sync" do
    before do
      extension.send(:handle_register_project, {
        "jira_project_key" => "PROJ",
        "kiket_project_id" => "kiket-123"
      }, context)
    end

    it "triggers a sync job" do
      result = extension.send(:handle_trigger_sync, {
        "jira_project_key" => "PROJ",
        "sync_type" => "full"
      }, context)

      expect(result[:status]).to eq("triggered")
      expect(result[:job][:sync_type]).to eq("full")
      expect(result[:job][:state]).to eq("pending")
    end
  end

  describe "#handle_list_sync_jobs" do
    before do
      extension.send(:handle_register_project, {
        "jira_project_key" => "PROJ",
        "kiket_project_id" => "kiket-123"
      }, context)

      extension.send(:handle_trigger_sync, {
        "jira_project_key" => "PROJ",
        "sync_type" => "full"
      }, context)
    end

    it "lists sync jobs" do
      result = extension.send(:handle_list_sync_jobs, {}, context)

      expect(result[:jobs]).to be_an(Array)
      expect(result[:jobs].length).to eq(1)
    end

    it "filters by project" do
      result = extension.send(:handle_list_sync_jobs, {
        "jira_project_key" => "PROJ"
      }, context)

      expect(result[:jobs].length).to eq(1)
    end
  end

  describe "#handle_receive_webhook" do
    before do
      extension.send(:handle_register_project, {
        "jira_project_key" => "PROJ",
        "kiket_project_id" => "kiket-123"
      }, context)
    end

    it "handles issue_updated webhook" do
      payload = {
        "event_type" => "jira:issue_updated",
        "issue" => {
          "key" => "PROJ-1",
          "fields" => {
            "summary" => "Test issue",
            "status" => { "name" => "In Progress" }
          }
        }
      }

      result = extension.send(:handle_receive_webhook, payload, context)

      expect(result[:status]).to eq("received")
      expect(result[:event_type]).to eq("jira:issue_updated")
    end

    it "handles issue_created webhook" do
      payload = {
        "event_type" => "jira:issue_created",
        "issue" => {
          "key" => "PROJ-2",
          "fields" => {
            "summary" => "New issue"
          }
        }
      }

      result = extension.send(:handle_receive_webhook, payload, context)

      expect(result[:status]).to eq("received")
    end
  end

  describe "#handle_sync_report" do
    before do
      extension.send(:handle_register_project, {
        "jira_project_key" => "PROJ",
        "kiket_project_id" => "kiket-123"
      }, context)

      extension.send(:handle_create_mapping, {
        "jira_project_key" => "PROJ",
        "jira_issue_key" => "PROJ-1",
        "kiket_issue_id" => "ISSUE-123"
      }, context)
    end

    it "generates sync report" do
      result = extension.send(:handle_sync_report, {}, context)

      expect(result[:total_projects]).to eq(1)
      expect(result[:total_mappings]).to eq(1)
    end

    it "filters by project" do
      result = extension.send(:handle_sync_report, {
        "jira_project_key" => "PROJ"
      }, context)

      expect(result[:mappings_count]).to eq(1)
    end
  end

  describe "#handle_export_mappings" do
    before do
      extension.send(:handle_register_project, {
        "jira_project_key" => "PROJ",
        "kiket_project_id" => "kiket-123"
      }, context)

      extension.send(:handle_create_mapping, {
        "jira_project_key" => "PROJ",
        "jira_issue_key" => "PROJ-1",
        "kiket_issue_id" => "ISSUE-123"
      }, context)
    end

    it "exports mappings as CSV" do
      result = extension.send(:handle_export_mappings, {}, context)

      expect(result[:content_type]).to eq("text/csv")
      expect(result[:data]).to include("PROJ-1")
      expect(result[:data]).to include("ISSUE-123")
    end
  end
end
