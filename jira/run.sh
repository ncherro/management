#!/bin/bash

FILES=./data/*.json
for f in $FILES
do
  # iterate over files, building args
  for users in `cat $f | jq -j '.members[] | "\(.jira_username)|\(.start_date)|\(.end_date),"' | rev | cut -c 2- | rev`
  do
    board_id="$(cat $f | jq '.team.board_id')"
    team_key="$(cat $f | jq '.team.key' | tr -d '"')"
    ts="$(date -u +'%Y-%m-%dT%H:%M:%SZ')"
    args="${board_id} ${users} /tmp/output/${team_key}-${ts}.csv"

    # call the script
    bundle exec ruby ./calculate-team-velocity.rb $args
  done
done
