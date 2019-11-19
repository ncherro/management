#!/usr/bin/env ruby

# This script queries Jira and outputs a CSV of Jira ticket summaries, URL,
# start date, and due dates
#
# export JIRA_EMAIL=my-jira-email
# export JIRA_API_KEY=my-jira-api-key
# export JIRA_BASE_URL=https://jira.company.com
#
# Arguments
# - JQL query to find matching issues
#
# $ ./generate.rb "project = WORK AND duedate != EMPTY"

require 'csv'
require 'date'
require 'fileutils'
require 'json'
require 'net/http'
require 'pry'
require 'uri'

JIRA_EMAIL = ENV.fetch('JIRA_EMAIL').freeze
JIRA_API_KEY = ENV.fetch('JIRA_API_KEY').freeze
JIRA_BASE_URL = ENV.fetch('JIRA_BASE_URL').freeze

if ARGV.length != 1
  raise 'Exactly one argument is required - JQL'
end

# grab args
JQL = ARGV[0].freeze
CSV_FILE_OUTPUT = "/app/output/output-#{DateTime.now}.csv"

JIRA_PER_PAGE = 50.freeze

class Issue
  attr_reader :summary, :key, :due_date, :start_date, :due_date_history,
    :start_date_history, :status

  def initialize(data)
    fields = data['fields']
    @key = data['key']
    @summary = fields['summary']
    @due_date = fields['duedate']
    @start_date = fields['customfield_10016']
    @status = fields['status']['name']
    @due_date_history = []
    @start_date_history = []
    parse_changelog(data)
  end

  private

  def parse_history(histories)
    histories.each do |change|
      change['items'].each do |item|
        if item['field'] == 'duedate'
          @due_date_history << item['to']
        elsif item['field'] == 'Start date'
          @start_date_history << item['to']
        end
      end
    end
  end

  def parse_changelog(data)
    # TODO - implement changelog pagination
    parse_history(data['changelog']['histories'])
  end
end

# JiraClient wraps logic around connecting to Jira and executing JQL queries
class JiraClient
  def initialize(email:, api_key:, base_url:)
    @email = email
    @api_key = api_key
    @base_url = base_url
  end

  # query Jira using JQL
  def jql(q, fields: [], expand_changelog: false, page: 1)
    startAt = (page - 1) * JIRA_PER_PAGE
    qs = "jql=#{q}&startAt=#{startAt}&maxResults=#{JIRA_PER_PAGE}"
    fields.any? && qs += "&fields=#{fields.join(',')}"
    qs += '&expand=changelog' if expand_changelog
    parse_json(request(path: "rest/api/2/search?#{qs}"))
  end

  # execute JQL, iterating over all pages
  def jql_all(q, fields: [], expand_changelog: false)
    page = 1
    resp, _ = jql(
      q,
      fields: fields,
      expand_changelog: expand_changelog,
      page: page
    )
    issues = resp['issues']
    return issues if resp['total'] <= resp['startAt'] + resp['maxResults']
    loop do
      page += 1
      resp, _ = jql(
        q,
        fields: fields,
        expand_changelog: expand_changelog,
        page: page
      )
      issues += resp['issues']
      break if resp['total'] <= resp['startAt'] + resp['maxResults']
    end
    issues
  end

  private

  # request accepts a path, method, and optional data argument and executes a
  # REST API against Jira, using the username, password, and base url assigned
  # above
  #
  # returns a Net::HTTP response object
  def request(path:, method: 'GET', data: nil)
    uri = URI.parse("#{@base_url}/#{path}")
    case method
    when 'GET'
      request = Net::HTTP::Get.new(uri)
    when 'POST'
      request = Net::HTTP::Post.new(uri)
    else
      raise "Unsupported HTTP method: #{method}"
    end
    request.basic_auth(@email, @api_key)
    request.content_type = 'application/json'
    request.body = data.to_json if method == 'POST'

    req_options = {
      use_ssl: uri.scheme == 'https'
    }

    response = Net::HTTP.start(uri.hostname, uri.port, req_options) do |http|
      http.request(request)
    end

    response
  end

  # parse_json parses a Net::HTTP response body into a JSON json object
  # it returns the parsed body, and the response code
  def parse_json(response)
    [JSON.parse(response.body), response.code]
  end
end

# instantiate a Jira client
JIRA_CLIENT = JiraClient.new(
  email: JIRA_EMAIL,
  api_key: JIRA_API_KEY,
  base_url: JIRA_BASE_URL
)

# fetch the issues
issues_raw = JIRA_CLIENT.jql_all(
  JQL,
  expand_changelog: true,
  fields: %w(customfield_10016 summary duedate status)
)

issues = issues_raw.map do |issue_data|
  Issue.new(issue_data)
end

CSV.open(CSV_FILE_OUTPUT, 'wb') do |csv|
  csv << %w(key summary status start_date due_date start_date_history
  due_date_history)
  issues.each do |issue|
    csv << [
      issue.key,
      issue.summary,
      issue.status,
      issue.start_date,
      issue.due_date,
      issue.start_date_history.join(','),
      issue.due_date_history.join(',')
    ]
  end
end

puts "Done! - check the output dir"
