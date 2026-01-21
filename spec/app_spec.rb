# frozen_string_literal: true

require 'spec_helper'

RSpec.describe JiraExtension do
  subject(:extension) { described_class.new }

  let(:context) { build_context }

  describe '#handle_register_project' do
    let(:payload) do
      {
        'jira_project_key' => 'PROJ',
        'kiket_project_id' => 'kiket-123',
        'jira_url' => 'https://example.atlassian.net',
        'sync_direction' => 'bidirectional'
      }
    end

    it 'registers a new project' do
      result = extension.send(:handle_register_project, payload, context)

      expect(result[:status]).to eq('registered')
      expect(result[:project][:jira_project_key]).to eq('PROJ')
      expect(result[:project][:kiket_project_id]).to eq('kiket-123')
    end

    it 'requires jira_project_key, kiket_project_id, and jira_url' do
      result = extension.send(:handle_register_project, {}, context)

      expect(result[:error]).not_to be_nil
    end
  end

  describe '#handle_list_projects' do
    before do
      extension.send(:handle_register_project, {
                       'jira_project_key' => 'PROJ',
                       'kiket_project_id' => 'kiket-123',
                       'jira_url' => 'https://example.atlassian.net'
                     }, context)
    end

    it 'lists all projects' do
      result = extension.send(:handle_list_projects, {}, context)

      expect(result[:projects]).to be_an(Array)
      expect(result[:projects].length).to eq(1)
    end
  end

  describe '#handle_delete_project' do
    let!(:project_result) do
      extension.send(:handle_register_project, {
                       'jira_project_key' => 'PROJ',
                       'kiket_project_id' => 'kiket-123',
                       'jira_url' => 'https://example.atlassian.net'
                     }, context)
    end

    it 'deletes a project' do
      result = extension.send(:handle_delete_project, {
                                'id' => project_result[:project][:id]
                              }, context)

      expect(result[:status]).to eq('deleted')

      list_result = extension.send(:handle_list_projects, {}, context)
      expect(list_result[:projects].length).to eq(0)
    end
  end

  describe '#handle_map_issue' do
    let!(:project_result) do
      extension.send(:handle_register_project, {
                       'jira_project_key' => 'PROJ',
                       'kiket_project_id' => 'kiket-123',
                       'jira_url' => 'https://example.atlassian.net'
                     }, context)
    end

    it 'creates an issue mapping' do
      result = extension.send(:handle_map_issue, {
                                'project_id' => project_result[:project][:id],
                                'jira_issue_key' => 'PROJ-1',
                                'kiket_issue_id' => 'ISSUE-123'
                              }, context)

      expect(result[:status]).to eq('mapped')
      expect(result[:mapping][:jira_issue_key]).to eq('PROJ-1')
      expect(result[:mapping][:kiket_issue_id]).to eq('ISSUE-123')
    end
  end

  describe '#handle_list_issue_mappings' do
    let!(:project_result) do
      extension.send(:handle_register_project, {
                       'jira_project_key' => 'PROJ',
                       'kiket_project_id' => 'kiket-123',
                       'jira_url' => 'https://example.atlassian.net'
                     }, context)
    end

    before do
      extension.send(:handle_map_issue, {
                       'project_id' => project_result[:project][:id],
                       'jira_issue_key' => 'PROJ-1',
                       'kiket_issue_id' => 'ISSUE-123'
                     }, context)
    end

    it 'lists all mappings' do
      result = extension.send(:handle_list_issue_mappings, {}, context)

      expect(result[:mappings]).to be_an(Array)
      expect(result[:mappings].length).to eq(1)
    end

    it 'filters by project' do
      result = extension.send(:handle_list_issue_mappings, {
                                'project_id' => project_result[:project][:id]
                              }, context)

      expect(result[:mappings].length).to eq(1)
    end
  end

  describe '#handle_map_field' do
    let!(:project_result) do
      extension.send(:handle_register_project, {
                       'jira_project_key' => 'PROJ',
                       'kiket_project_id' => 'kiket-123',
                       'jira_url' => 'https://example.atlassian.net'
                     }, context)
    end

    it 'creates a field mapping' do
      result = extension.send(:handle_map_field, {
                                'project_id' => project_result[:project][:id],
                                'jira_field_id' => 'customfield_10001',
                                'kiket_field_name' => 'story_points',
                                'field_type' => 'integer'
                              }, context)

      expect(result[:status]).to eq('mapped')
      expect(result[:mapping][:jira_field_id]).to eq('customfield_10001')
      expect(result[:mapping][:kiket_field_name]).to eq('story_points')
    end
  end

  describe '#handle_map_status' do
    let!(:project_result) do
      extension.send(:handle_register_project, {
                       'jira_project_key' => 'PROJ',
                       'kiket_project_id' => 'kiket-123',
                       'jira_url' => 'https://example.atlassian.net'
                     }, context)
    end

    it 'creates a status mapping' do
      result = extension.send(:handle_map_status, {
                                'project_id' => project_result[:project][:id],
                                'jira_status_id' => '10001',
                                'jira_status_name' => 'In Progress',
                                'kiket_status' => 'in_progress'
                              }, context)

      expect(result[:status]).to eq('mapped')
      expect(result[:mapping][:jira_status_name]).to eq('In Progress')
      expect(result[:mapping][:kiket_status]).to eq('in_progress')
    end
  end

  describe '#handle_trigger_sync' do
    let!(:project_result) do
      extension.send(:handle_register_project, {
                       'jira_project_key' => 'PROJ',
                       'kiket_project_id' => 'kiket-123',
                       'jira_url' => 'https://example.atlassian.net'
                     }, context)
    end

    it 'triggers a sync job' do
      result = extension.send(:handle_trigger_sync, {
                                'project_id' => project_result[:project][:id],
                                'sync_type' => 'full'
                              }, context)

      expect(result[:status]).to eq('triggered')
      expect(result[:job][:sync_type]).to eq('full')
      expect(result[:job][:status]).to eq('running')
    end
  end

  describe '#handle_list_sync_jobs' do
    let!(:project_result) do
      extension.send(:handle_register_project, {
                       'jira_project_key' => 'PROJ',
                       'kiket_project_id' => 'kiket-123',
                       'jira_url' => 'https://example.atlassian.net'
                     }, context)
    end

    before do
      extension.send(:handle_trigger_sync, {
                       'project_id' => project_result[:project][:id],
                       'sync_type' => 'full'
                     }, context)
    end

    it 'lists sync jobs' do
      result = extension.send(:handle_list_sync_jobs, {}, context)

      expect(result[:jobs]).to be_an(Array)
      expect(result[:jobs].length).to eq(1)
    end

    it 'filters by project' do
      result = extension.send(:handle_list_sync_jobs, {
                                'project_id' => project_result[:project][:id]
                              }, context)

      expect(result[:jobs].length).to eq(1)
    end
  end

  describe '#handle_jira_webhook' do
    before do
      extension.send(:handle_register_project, {
                       'jira_project_key' => 'PROJ',
                       'kiket_project_id' => 'kiket-123',
                       'jira_url' => 'https://example.atlassian.net'
                     }, context)
    end

    it 'handles issue_updated webhook' do
      payload = {
        'event_type' => 'jira:issue_updated',
        'raw_payload' => {
          'webhookEvent' => 'jira:issue_updated',
          'issue' => {
            'key' => 'PROJ-1',
            'fields' => {
              'summary' => 'Test issue',
              'status' => { 'name' => 'In Progress' }
            }
          }
        }
      }

      result = extension.send(:handle_jira_webhook, payload, context)

      expect(result[:status]).to eq('received')
      expect(result[:delivery_id]).not_to be_nil
    end

    it 'handles issue_created webhook' do
      payload = {
        'event_type' => 'jira:issue_created',
        'raw_payload' => {
          'webhookEvent' => 'jira:issue_created',
          'issue' => {
            'key' => 'PROJ-2',
            'fields' => {
              'summary' => 'New issue'
            }
          }
        }
      }

      result = extension.send(:handle_jira_webhook, payload, context)

      expect(result[:status]).to eq('received')
    end
  end

  describe '#handle_sync_metrics' do
    let!(:project_result) do
      extension.send(:handle_register_project, {
                       'jira_project_key' => 'PROJ',
                       'kiket_project_id' => 'kiket-123',
                       'jira_url' => 'https://example.atlassian.net'
                     }, context)
    end

    before do
      extension.send(:handle_map_issue, {
                       'project_id' => project_result[:project][:id],
                       'jira_issue_key' => 'PROJ-1',
                       'kiket_issue_id' => 'ISSUE-123'
                     }, context)
      extension.send(:handle_trigger_sync, {
                       'project_id' => project_result[:project][:id],
                       'sync_type' => 'full'
                     }, context)
    end

    it 'generates sync metrics' do
      result = extension.send(:handle_sync_metrics, {}, context)

      expect(result[:total_jobs]).to eq(1)
      expect(result[:active_mappings]).to eq(1)
    end

    it 'filters by project' do
      result = extension.send(:handle_sync_metrics, {
                                'project_id' => project_result[:project][:id]
                              }, context)

      expect(result[:total_jobs]).to eq(1)
    end
  end

  describe '#handle_export_mappings' do
    let!(:project_result) do
      extension.send(:handle_register_project, {
                       'jira_project_key' => 'PROJ',
                       'kiket_project_id' => 'kiket-123',
                       'jira_url' => 'https://example.atlassian.net'
                     }, context)
    end

    before do
      extension.send(:handle_map_issue, {
                       'project_id' => project_result[:project][:id],
                       'jira_issue_key' => 'PROJ-1',
                       'kiket_issue_id' => 'ISSUE-123'
                     }, context)
    end

    it 'exports mappings as CSV' do
      result = extension.send(:handle_export_mappings, {}, context)

      expect(result[:format]).to eq('csv')
      expect(result[:content]).to include('PROJ-1')
      expect(result[:content]).to include('ISSUE-123')
    end
  end
end
