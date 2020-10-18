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
CSV_FILE_OUTPUT = "/app/output/output.csv"

JIRA_PER_PAGE = 50.freeze

FIELD_MAP = {
  'key' => 'key',
  'status' => 'status',
  'summary' => 'summary',
  'original_start_date' => 'customfield_10054',
  'original_due_date' => 'customfield_10055',
  'start_date' => 'customfield_10016',
  'due_date' => 'duedate',
  'qa_days_required' => 'customfield_10056',
  'ship_date' => 'customfield_10057',
  'rank' => 'customfield_10009',
  'eng_team' => 'customfield_10064',
  'product_spec_url' => 'customfield_10061',
  'tech_spec_url' => 'customfield_10062'
}

class Issue
  attr_reader :dev_days

  def initialize(data)
    fields = data['fields']

    @key = data['key']
    @status = fields['status']['name']
    @summary = fields[FIELD_MAP['summary']]

    @original_start_date = fields[FIELD_MAP['original_start_date']]
    @original_due_date = fields[FIELD_MAP['original_due_date']]
    @start_date = fields[FIELD_MAP['start_date']]
    @due_date = fields[FIELD_MAP['due_date']]
    @qa_days_required = fields[FIELD_MAP['qa_days_required']]
    @ship_date = fields[FIELD_MAP['ship_date']]
    @rank = fields[FIELD_MAP['rank']]
    @eng_team = fields[FIELD_MAP['eng_team']]
    @product_spec_url = fields[FIELD_MAP['product_spec_url']]
    @tech_spec_url = fields[FIELD_MAP['tech_spec_url']]

    @dev_days = 0
    if @start_date && @due_date
      @dev_days = (Date.parse(@due_date) - Date.parse(@start_date)).to_i
    end
  end
end

# HACK!
FIELD_MAP.keys.each do |k|
  Issue.class_eval("attr_reader :#{k}")
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
  fields: FIELD_MAP.values
)

issues = issues_raw.map do |issue_data|
  Issue.new(issue_data)
end.sort_by { |issue| issue.due_date }

headers = FIELD_MAP.keys + ['dev_days']
CSV.open(CSV_FILE_OUTPUT, 'wb') do |csv|
  csv << headers
  issues.each do |issue|
    csv << FIELD_MAP.keys.map { |k| issue.send(k.to_sym) } + [issue.dev_days]
  end
end

puts "Done! - check the output dir"
