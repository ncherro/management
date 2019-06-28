# Jira Team Velocity Calculator

## Prereqs

Docker

## Instructions

1. create files in the `data` dir describing your teams (see `data/README.md`
   for details)
1. `export JIRA_USERNAME=[your jira username]`
1. `export JIRA_PASSWORD=[your jira password]`
1. `export JIRA_BASE_URL=[your jira base url - e.g https://jira.company.com]`
1. `make build`
1. `make run`

Then check the `output` directory for a list of CSV files - one per team
described in `data`
