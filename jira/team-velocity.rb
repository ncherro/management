#!/usr/bin/env ruby

# This script queries Jira and outputs a CSV file containing counts for team
# members, including averages and sum / percentage delta for each member
#
# Tested using Ruby v2.5
#
# export JIRA_USERNAME=my-jira-username
# export JIRA_PASSWORD=my-jira-password
# export JIRA_BOARD_ID=1234
# export JIRA_BASE_URL=https://jira.company.com (optional)
#
# Arguments
# - comma-separated list of username|start-date
# - /path/to/output.csv
#
# Sample:
# $ ./query.rb "john.doe|2019-01-01,jane.doe|2018-05-17" /path/to/output.csv

require 'csv'
require 'net/http'
require 'uri'
require 'json'
require 'fileutils'

# uncomment, and `gem install pry-coolline`, to debug
require 'pry-coolline'

JIRA_USERNAME = ENV.fetch('JIRA_USERNAME').freeze
JIRA_PASSWORD = ENV.fetch('JIRA_PASSWORD').freeze
JIRA_BOARD_ID = ENV.fetch('JIRA_BOARD_ID').freeze
JIRA_BASE_URL = ENV.fetch('JIRA_BASE_URL', 'https://jira.namely.land').freeze

JIRA_KEY_STORY_POINTS = 'customfield_10005'.freeze
JIRA_KEY_ISSUE_TYPE = 'issuetype'.freeze
JIRA_KEY_LABELS = 'labels'.freeze
JIRA_KEY_PROJECT = 'project'.freeze

JIRA_FIELD_NAME_STORY_POINTS = 'Story Points'.freeze

if ARGV.length != 2
  raise 'Two arguments are required - list of users, and path to output file'
end

# grab args
EMPLOYEES = ARGV[0].freeze
CSV_FILE = ARGV[1].freeze

# if JIRA_CACHE_FILE is set as an env var, then JQL data will be cached to it -
# key = query, val = the response (json)
JIRA_CACHE_FILE = ENV.fetch('JIRA_CACHE_FILE', nil)
SHRUG_DELIMITER = ' |¯\_(ツ)_/¯| '.freeze
if JIRA_CACHE_FILE
  FileUtils.touch(JIRA_CACHE_FILE)
  JIRA_CACHE = {}
  File.readlines(JIRA_CACHE_FILE).each do |line|
    k, v = line.split(SHRUG_DELIMITER, 2)
    JIRA_CACHE[k] = v
  end
else
  JIRA_CACHE = nil
end

# JiraClient wraps logic around connecting to Jira and executing JQL queries
class JiraClient
  def initialize(username:, password:, base_url:)
    @username = username
    @password = password
    @base_url = base_url
  end

  # jql queries Jira using jql
  #
  # TODO: handle multiple pages of results
  def jql(jql, fields: [], startAt: 0)
    qs = "jql=#{jql}&startAt=#{startAt}&maxResults=100"
    fields.any? && qs += "&fields=#{fields.join(',')}"
    parse_json(request(path: "rest/api/2/search?#{qs}"))
  end

  # max_points iterates over a list of Jira issues, finds the max number of
  # story points per issue, and returns a hash with jira_key => max_points
  def max_points_for_issues(issues)
    issues.map do |issue|
      path = "#{issue['self'].sub("#{@base_url}/", '')}?expand=changelog&" \
        "fields=changelog,#{JIRA_KEY_STORY_POINTS}"
      resp, status = parse_json(request(path: path))
      raise "Error getting history - #{path}" if status != '200'

      resp['fields'] ||= {} # handle BR tickets
      orig_points = resp['fields'][JIRA_KEY_STORY_POINTS].to_i

      points_found = [orig_points]
      resp['changelog']['histories'].each do |log|
        point_changes = log['items'].select do |item|
          item['field'] == JIRA_FIELD_NAME_STORY_POINTS
        end
        points_found += point_changes.map { |pc| pc['toString'].to_i }
      end

      # sanity check
      # binding.pry if points_found.compact.max > orig_points

      [issue['key'], points_found.compact.max]
    end.to_h
  end

  # closed_sprints returns a list of sprints belonging to the JIRA_BOARD_ID
  # that have been closed - it provides timespans we report against
  def closed_sprint_times
    per_page = 50
    offset = 0
    path = "rest/agile/1.0/board/#{JIRA_BOARD_ID}/sprint?maxResults=#{per_page}"
    sprints = []
    data, status = parse_json(request(path: path))
    loop do
      sprints += data['values'].select { |s| s['state'] == 'closed' }
      break if data['isLast'] || status != '200'

      offset += per_page
      data, status = parse_json(request(path: "#{path}&startAt=#{offset}"))
    end
    # sort by startDate and map to [startDate, endDate]
    times = sprints.sort_by { |s| s['startDate'] }.map do |s|
      [DateTime.parse(s['startDate']), DateTime.parse(s['endDate'])]
    end
    # ensure there are no gaps
    times.each_with_index do |time, idx|
      next_time = times[idx + 1]
      time[1] = next_time[0] if next_time
    end
    times
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
    when 'POST'
      request = Net::HTTP::Post.new(uri)
    else
      raise "Unsupported HTTP method: #{method}"
    end
    request.basic_auth(@username, @password)
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

  # pares_json parses a Net::HTTP response body into a JSON json object
  # it returns the parsed body, and the response code
  def parse_json(response)
    [JSON.parse(response.body), response.code]
  end
end

# instantiate a Jira client
JIRA_CLIENT = JiraClient.new(
  username: JIRA_USERNAME,
  password: JIRA_PASSWORD,
  base_url: JIRA_BASE_URL
)

# Employee describes a direct report
class Employee
  attr_reader :username, :start_date, :counts

  def initialize(username:, start_date:)
    @username = username
    @start_date = Date.parse(start_date)
    @counts = {}
  end

  def active_on?(date_s)
    @start_date < Date.parse(date_s)
  end

  def set_counts
    jql = "engineer=#{@username} AND resolution=Done"

    JIRA_CLIENT.closed_sprint_times.each do |times|
      start_time = JIRA_CLIENT.format_time(times[0])
      end_time = JIRA_CLIENT.format_time(times[1])
      unless active_on?(start_time)
        # person was not on team yet
        @counts[start_time] = { 'total' => 0, 'issues' => [] }
        next
      end

      q = "#{jql} AND resolutiondate >= \"#{start_time}\" AND resolutiondate < \"#{end_time}\""

      # check the cache first
      data = nil
      if JIRA_CACHE && JIRA_CACHE[q]
        data = JSON.parse(JIRA_CACHE[q])
      else
        p "Fetching #{q}"

        # fetch issues, only concerned about the story points
        data, status = JIRA_CLIENT.jql(
          q,
          fields: [JIRA_KEY_STORY_POINTS, JIRA_KEY_ISSUE_TYPE, JIRA_KEY_LABELS,
                   JIRA_KEY_PROJECT]
        )

        raise "Error getting #{@username} - #{q}\n#{data}" if status != '200'

        if data['issues'].any?
          points_map = JIRA_CLIENT.max_points_for_issues(data['issues'])
          # override the points
          data['issues'].each do |issue|
            issue['fields'] ||= {} # handle BR tickets
            issue['fields'][JIRA_KEY_STORY_POINTS] = points_map[issue['key']]
          end
        end

        if JIRA_CACHE
          # write it to the file
          File.open(JIRA_CACHE_FILE, 'a') do |f|
            f << "#{q}#{SHRUG_DELIMITER}#{data.to_json}\n"
          end
        end
      end

      @counts[start_time] = data
    end
  end
end

def crunch_numbers
  # set up EEs
  ees = []

  EMPLOYEES.split(',').each do |item|
    username, start_date = item.split('|')
    ees << Employee.new(username: username, start_date: start_date)
  end
  ees.each(&:set_counts)

  # prep the data
  csv_data = []
  average_issues = {}
  average_points = {}
  ees.each do |ee|
    ee.counts.each do |date, data|
      # first few weeks don't count
      points = data['issues'].map do |issue|
        (issue['fields'][JIRA_KEY_STORY_POINTS] || 0).to_i
      end
      total_points = points.reduce(&:+) || 0

      csv_data << [
        ee.username,
        date,
        data['total'],
        total_points,
        ee.active_on?(date)
      ]

      next unless ee.active_on?(date)

      # populate the averages
      average_issues[date] ||= []
      average_points[date] ||= []
      average_issues[date] << data['total']
      average_points[date] << total_points
    end
  end

  # calcuate averages
  average_issues.each do |date, val|
    len = val.count
    average_issues[date] = (val.reduce(&:+) / len.to_f).round(2)
  end
  average_points.each do |date, val|
    len = val.count
    average_points[date] = (val.reduce(&:+) / len.to_f).round(2)
  end

  headers = %w[user sprint_start total_issues total_points active average_issues_delta_sum average_issues_delta_perc average_points_delta_sum average_points_delta_perc]
  CSV.open(CSV_FILE, 'w+') do |csv|
    csv << headers

    average_issues.each do |date, val|
      csv << ['average', date, val, average_points[date], true, 0, 0, 0, 0]
    end

    csv_data.each do |row|
      date = row[1]
      total_issues = row[2]
      total_points = row[3]
      is_active = row[4]

      average_issues_delta_sum = average_issues_delta_perc =
        average_points_delta_sum = average_points_delta_perc = 0

      if is_active
        average_issues_delta_sum = (total_issues - average_issues[date]).round(2)
        if average_issues[date] == 0
        else
          average_issues_delta_perc = (total_issues / average_issues[date]).round(2)
        end

        average_points_delta_sum = (total_points - average_points[date]).round(2)
        if average_points[date] == 0
          average_points_delta_perc = 1.0
        else
          average_points_delta_perc = (total_points / average_points[date]).round(2)
        end
      end

      csv << row + [
        average_issues_delta_sum,
        average_issues_delta_perc,
        average_points_delta_sum,
        average_points_delta_perc
      ]
    end
  end

  nil
end

crunch_numbers

puts "Done! - exported data to #{CSV_FILE}"
