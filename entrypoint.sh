function trigger_workflow {
  echo "Triggering ${INPUT_EVENT_TYPE} in ${INPUT_OWNER}/${INPUT_REPO}"

  workflow_expect_runid=$(curl -s "https://api.github.com/repos/${INPUT_OWNER}/${INPUT_REPO}/actions/runs?event=repository_dispatch" \
        -H "Accept: application/vnd.github.v3+json" \
        -H "Authorization: Bearer ${INPUT_TOKEN}" | jq '.workflow_runs[0].run_number')

  if [ "$workflow_expect_runid" = "null" ]; then
    workflow_expect_runid=0
  fi
  workflow_expect_runid=$(( $workflow_expect_runid + 1))

  resp=$(curl -X POST -s "https://api.github.com/repos/${INPUT_OWNER}/${INPUT_REPO}/dispatches" \
    -H "Accept: application/vnd.github.v3+json" \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer ${INPUT_TOKEN}" \
    -d "{\"event_type\": \"${INPUT_EVENT_TYPE}\", \"client_payload\": ${INPUT_CLIENT_PAYLOAD} }")

  if [ -z "$resp" ]
  then
    sleep 2
  else
    echo "Workflow failed to trigger"
    echo "$resp"
    exit 1
  fi
}

function ensure_workflow {
  max_wait=10
  stime=$(date +%s)
  while [ $(( `date +%s` - $stime )) -lt $max_wait ]
  do
    workflow_runid=$(curl -s "https://api.github.com/repos/${INPUT_OWNER}/${INPUT_REPO}/actions/runs?event=repository_dispatch" \
      -H "Accept: application/vnd.github.v3+json" \
      -H "Authorization: Bearer ${INPUT_TOKEN}" | jq ".workflow_runs[] | select(.run_number==$workflow_expect_runid) | .id")

    if [ -z "$workflow_runid" ]; then
      >&2 echo "Repository dispatch failed! No workflow run id found."
      exit 1
    fi

    sleep 2
  done
  echo "Workflow run id is ${workflow_runid}"
}

function wait_on_workflow {
  stime=$(date +%s)
  conclusion="null"

  while [[ $conclusion == "null" ]]
  do
    rtime=$(( `date +%s` - $stime ))
    if [[ "$rtime" -ge "$INPUT_MAX_TIME" ]]
    then
      echo "Time limit exceeded"
      exit 1
    fi
    sleep $INPUT_WAIT_TIME
    conclusion=$(curl -s "https://api.github.com/repos/${INPUT_OWNER}/${INPUT_REPO}/actions/runs/${wfid}" \
    	-H "Accept: application/vnd.github.v3+json" \
    	-H "Authorization: Bearer ${INPUT_TOKEN}" | jq -r '.conclusion')

    if [ "$conclusion" == "failure" ]; then
      break
    fi
  done

  if [[ $conclusion == "success" ]]
  then
    echo "Workflow run successful"
  else
    echo "Workflow run failed (conclusion: $conclusion)"
    exit 1
  fi
}

function main {
  trigger_workflow
  ensure_workflow
  wait_on_workflow
}

main
