# Jira Team Velocity Calculator

## Prereqs

Docker

## Instructions

1. create files in the `data` dir - see instructions below
1. `export JIRA_USERNAME=my-jira-username`
1. `export JIRA_PASSWORD=my-jira-password`
1. `export JIRA_BASE_URL=https://company.atlassian.com`
1. `make build`
1. `make run`

Then check the `output` directory for a list of CSV files - one per team
described in the `data` dir

### Files in the data dir

Enter files in `data` describe your teams, e.g.

`myteam.json`

```json
{
  "team": {
    "board_id": 312,
    "key": "foo",
    "units": "points",
    "burndown": true
  },
  "members": [
    {
      "jira_username": "john.doe",
      "start_date": "2019-03-04"
    },
    {
      "jira_username": "jane.doe",
      "start_date": "2018-09-04",
      "end_date": "2019-06-28"
    }
  ]
}
```

Notes:

- `team.board_id` is used to pull closed sprint dates. JQL queries scope to
  these dates, but not to the sprints (you'll get counts / points for issues
  completed on any board / project during the sprint)
- `team.units` must be set to 'points' or 'hours'
- `team.burndown` should be set to `true` if the team 'burns down' points
  before the end of a sprint. if `true`, the script will evaluate the *max*
  number of points for a given ticket
