#!/usr/bin/env ruby

# This script queries Jira and outputs a CSV file containing counts for team
# members, including averages and sum / percentage delta for each member
#
# Tested using Ruby v2.5
#
# export JIRA_EMAIL=my-jira-email
# export JIRA_API_KEY=my-jira-api-key
# export JIRA_BASE_URL=https://jira.company.com
#
# Arguments
# - jira project key
# - jira issue type key
# - /path/to/import-file.csv
#
# Sample:
# $ ./create-issues.rb FOO "Data Fix" /path/to/import-file.csv

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

if ARGV.length != 3
  raise 'Three arguments are required - Project key, Issue Type key, and path to input file'
end

# grab args
JIRA_PROJECT_KEY = ARGV[0].freeze
JIRA_ISSUE_TYPE_KEY = ARGV[1].freeze
CSV_FILE = ARGV[2].freeze
CSV_FILE_OUTPUT = "/app/output/output-#{DateTime.now}.csv"

# CSV headers => Jira keys
FIELD_MAPPINGS = {
  # 'Done?' => '', - set in subsequent import
  # 'Date' => '', - set in subsequent import
  'Reporter' => 'reporter',
  'Summary' => 'summary',
  'Description' => 'description',
}.freeze

FIELD_MAPPINGS_CUSTOM = {
  'User ID' => 'User ID',
  'Station ID' => 'Station ID',
  'Episode ID' => 'Episode ID',
  'Audio ID' => 'Audio ID',
  'Email' => 'User Email',
  'Zendesk Ticket' => 'Zendesk Ticket',
  'Blocking Issues' => 'Blocking Issues',
  'Resolution/Notes' => 'Resolution Comment',
  'Slack link' => 'Slack Link',
  # 'Jira link' => '',
}.freeze

# Custom value mappings
VALUE_MAPPINGS = {
  'Reporter' => {
    'Dassy' => 'dassy',
    'Miranda' => 'mirandad',
    'Grant' => 'grant',
    'lauren' => 'lauren',
    'Lauren' => 'lauren',
    'Jenna' => 'jenna',
    'Ana' => 'ana',
    'Jess' => 'jessica',
    'Niki' => 'niki',
    'Vin' => 'vin',
  },
}.freeze

# JiraClient wraps logic around connecting to Jira and executing JQL queries
class JiraClient
  def initialize(email:, api_key:, base_url:)
    @email = email
    @api_key = api_key
    @base_url = base_url
  end

  def get_metadata
    issue_type_key = JIRA_ISSUE_TYPE_KEY.split(' ').join('+')
    path = "rest/api/2/issue/createmeta?projectKeys=#{JIRA_PROJECT_KEY}&issuetypeNames=#{issue_type_key}&expand=projects.issuetypes.fields"
    parse_json(request(path: path))
  end

  def create_issue(data)
    path = "rest/api/2/issue"
    fields = {
      'project' => {
        'key' => JIRA_PROJECT_KEY
      },
      'issuetype' => {
        'name' => JIRA_ISSUE_TYPE_KEY
      }
    }.merge(data)
    parse_json(request(path: path, method: 'POST', data: { 'fields': fields }))
  end

  # format_time accepts a DateTime object and returns a string that can be used
  # in JQL
  def format_time(dt)
    dt.strftime('%Y-%m-%d %H:%M')
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
    when 'PUT'
      request = Net::HTTP::Put.new(uri)
    when 'POST'
      request = Net::HTTP::Post.new(uri)
    else
      raise "Unsupported HTTP method: #{method}"
    end
    request.basic_auth(@email, @api_key)
    request.content_type = 'application/json'
    request.body = data.to_json if method == 'POST' || method == 'PUT'

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

# get the metadata
metadata = JIRA_CLIENT.get_metadata
fields = metadata[0]['projects'][0]['issuetypes'][0]['fields']

# parse the CSV
table = CSV.parse(File.read(CSV_FILE), headers: true)

# map fields
FIELD_MAPPINGS_ACTUAL = {}
table.headers.compact.each do |header|
  if FIELD_MAPPINGS[header]
    FIELD_MAPPINGS_ACTUAL[header] = FIELD_MAPPINGS[header]
  elsif FIELD_MAPPINGS_CUSTOM[header]
    # look it up
    jira_field_name = FIELD_MAPPINGS_CUSTOM[header]
    field = fields.select { |_, v| v['name'] == jira_field_name }
    raise "Could not find custom field for #{header}" if field == {}
    FIELD_MAPPINGS_ACTUAL[header] = field.values.first['key']
  end
end

# iterate over the CSV table and create tickets
CSV.open(CSV_FILE_OUTPUT, 'wb') do |csv|
  csv << %w(key created summary done)
  table.each do |row|
    row_data = row.to_h
    data = {}
    FIELD_MAPPINGS_ACTUAL.each do |csv_header, jira_attr|
      val = row_data[csv_header]
      next if val.nil? || val == ''

      val = val.strip

      # special cases
      if jira_attr == 'summary' || csv_header == 'Blocking Issues'
        val = val.gsub(/[[:space:]]+/, ' ').strip[0..254]
      end

      # value map, if necessary
      if VALUE_MAPPINGS[csv_header]
        # attempt to find the value mapping, fall back to original value
        val = VALUE_MAPPINGS[csv_header][val] || val
        # special case :(
        if csv_header == 'Reporter'
          val = { 'name' => val }
        end
      end

      # set the data
      data[jira_attr] = val
    end

    # skip if nothing to do
    next if data == {}

    resp, status = JIRA_CLIENT.create_issue(data)
    case status
    when '200', '201', '202'
      # append to our output csv
      csv << [resp['key'], row_data['Date'], data['summary'], row_data['Done?']]
      puts "Created #{resp['key']}"
    else
      puts "Failed to import - response status = #{status}"
      p row_data
      p data
      p resp
    end
  end
end

puts "Done! - now use the output file to run an import into Jira to set the created at date and issue statuses"
