
#!/bin/bash

# Utility for running github repo ci testing script against PRs
# Version: 1.0
# Author: Paul Carlton (mailto:paul.carlton@weave.works)

set -euo pipefail

function usage()
{
    echo "usage ${0} [--debug] [--comment]"
    echo "This script will look for new PRs and run the configured ci script against the PR branch"
    echo "--comment option causes comments to be written to PR containing test log"
}

function args() {
  debug=""
  comment=""
  arg_list=( "$@" )
  arg_count=${#arg_list[@]}
  arg_index=0
  while (( arg_index < arg_count )); do
    case "${arg_list[${arg_index}]}" in
          "--debug") set -x; debug="--debug";;
          "--comment") comment="--comment";;
               "-h") usage; exit;;
           "--help") usage; exit;;
               "-?") usage; exit;;
        *) if [ "${arg_list[${arg_index}]:0:2}" == "--" ];then
               echo "invalid argument: ${arg_list[${arg_index}]}"
               usage; exit
           fi;
           break;;
    esac
    (( arg_index+=1 ))
  done
}

function getPRs() {
  for pr in $(curl $curl_proxy_opt -s -H "Authorization: token $GITHUB_TOKEN" https://api.github.com/repos/$GITHUB_ORG_REPO/pulls | jq -r '.[].number')
  do
    processPR $pr
  done
}

function process_comments() {
   local check_updated="$1"
   details=$(curl $curl_proxy_opt -s -H "Authorization: token $GITHUB_TOKEN" -H "Accept: application/vnd.github.v3+json" https://api.github.com/repos/$GITHUB_ORG_REPO/issues/$pr/comments |\
      jq -r --arg CI_ID "$CI_ID check " '.[] | select( .body | ascii_downcase | startswith($CI_ID))' | jq -r '.created_at + "/" + .body' | sort -k 1 -t/ | tail -1)
   created=$(echo "$details" | cut -f1 -d/)
   action=$(echo "$details" | cut -f2 -d/ | cut -f3 -d" ")
   if [[ "$created" < "$check_updated" ]]; then
    return
  fi
  if [ "$action" == "rerun" ]; then
    set_check_pending $commit_sha
  fi

  if [ "$action" == "abort" ]; then
    ci_pid="$(get_ci_pid $commit_sha)"
    if [ -n "$ci_pid" ]; then
      kill -10 $ci_pid
    fi
    set_check_cancelled $commit_sha
    if [ -e  "$HOME/ci-$commit_sha.log" ]; then
      rm $HOME/ci-$parent_sha.log
    fi
  fi
}

function set_url() {  
  if [ -z "$comment" ] ; then
    echo "http://$host_name/pr$pr/ci-output.log"
  else
    echo "$host_name"
  fi
}

function set_check_pending() {
  local commit="$1"
  curl $curl_proxy_opt -s -X POST -H "Authorization: token $GITHUB_TOKEN" -H "Accept: application/vnd.github.v3+json" https://api.github.com/repos/$GITHUB_ORG_REPO/statuses/$commit \
    -d "{\"context\":\"$CI_ID\",\"description\": \"ci run pending\",\"state\":\"pending\", \"target_url\": \"$(set_url)\"}"
}

function set_check_cancelled() {
  local commit="$1"
  if [ -z "$comment" ] ; then
    url="http://$host_name/pr$pr/ci-output.log"
  else
    url="$host_name"
  fi
  curl $curl_proxy_opt -s -X POST -H "Authorization: token $GITHUB_TOKEN" -H "Accept: application/vnd.github.v3+json" https://api.github.com/repos/$GITHUB_ORG_REPO/statuses/$commit \
    -d "{\"context\":\"$CI_ID\",\"description\": \"ci run cancelled\",\"state\":\"error\", \"target_url\": \"$(set_url)\"}"
}

function processPR() {
  local draft=$(curl $curl_proxy_opt -s -H "Authorization: token $GITHUB_TOKEN" https://api.github.com/repos/$GITHUB_ORG_REPO/pulls/$pr | jq -r '.draft')
  if [ "$draft" == "true" ]; then
    echo "skipping draft PR: #$pr"
    return
  fi
  local branch=$(curl $curl_proxy_opt -s -H "Authorization: token $GITHUB_TOKEN" https://api.github.com/repos/$GITHUB_ORG_REPO/pulls/$pr | jq -r '.head.ref')
  commit_sha=$(curl $curl_proxy_opt -s -H "Authorization: token $GITHUB_TOKEN" https://api.github.com/repos/$GITHUB_ORG_REPO/commits/$branch | jq -r '.sha')
  details=$(curl $curl_proxy_opt -s -H "Authorization: token $GITHUB_TOKEN" -H "Accept: application/vnd.github.v3+json" https://api.github.com/repos/$GITHUB_ORG_REPO/statuses/$commit_sha \
    | jq -r --arg CI_ID "$CI_ID" '.[] | select( .context==$CI_ID)' | jq -r '.state + "/" + .updated_at + "/" + .description' | sort -k 2 -t/ | tail -1)
  status=$(echo "$details" | cut -f1 -d/)
  description=$(echo "$details" | cut -f3 -d/)
  updated=$(echo "$details" | cut -f2 -d/)
  if [ -n "$updated" ]; then
    process_comments $updated
  fi
  if [[ -z "$status" || "$status" == "pending" && "$description" == "ci run pending" ]]; then
    if [ -z "$status" ]; then
      set_check_pending $commit_sha
      cancel_parent
    else
      remove_completed_runs 
    fi
    slot="$(get_ci_slot)"
    if [ -n "$slot" ]; then
      nohup ci-runner.sh $debug $comment --pull-request $pr --commit-sha $commit_sha --url $(set_url)  2>&1 | sed s/$GITHUB_TOKEN/REDACTED/g > $(set_log_file) &
      ci_pid=$!
      add_ci_run $slot $commit_sha $ci_pid
    fi
  fi
}

function set_log_file() {
  if [ -n "$comment" ] ; then
    echo "/var/log/pr$pr-ci-output.log"
  else
    mkdir -p /var/www/html/pr$pr
    echo "/var/www/html/pr$pr/ci-output.log"
  fi
}

function cancel_parent() {
  local parent_sha
  parent_sha=$(curl $curl_proxy_opt -s -H "Authorization: token $GITHUB_TOKEN" https://api.github.com/repos/$GITHUB_ORG_REPO/commits/$branch | jq -r '.parents[0].sha')
  details=$(curl $curl_proxy_opt -s -H "Authorization: token $GITHUB_TOKEN" -H "Accept: application/vnd.github.v3+json" https://api.github.com/repos/$GITHUB_ORG_REPO/statuses/$parent_sha \
    | jq -r --arg CI_ID "$CI_ID" '.[] | select( .context==$CI_ID)' | jq -r '.state + "/" + .updated_at + "/" + .description' | sort -k 2 -t/ | tail -1)
  status=$(echo "$details" | cut -f1 -d/)
  description=$(echo "$details" | cut -f3 -d/)
  if [ "$status" == "pending" ]; then
    ci_pid="$(get_ci_pid $parent_sha)"
    if [ -n "$ci_pid" ]; then
      kill -10 $ci_pid
    fi
    set_check_cancelled $parent_sha
    if [ -e  "$HOME/ci-$parent_sha.log" ]; then
      rm $HOME/ci-$parent_sha.log
    fi
  fi
}

function add_ci_run() {
  local slot="$1"
  local commit_sha="$2"
  local ci_pid="$3"
  all_ci[$slot]="$commit_sha/$ci_pid"
  echo "${all_ci[@]}" > /etc/test-manager/ci-runs.txt
}

function get_ci_pid() {
  local the_commit="$1"
  for slot in ${!all_ci[@]}; do
    commit=$(echo "${all_ci[$slot]}" | cut -f1 -d/)
    if [ "$commit" == "$the_commit" ]; then
      pid=$(echo "${all_ci[$slot]}" | cut -f2 -d/)
      echo "$pid"
      return
    fi
  done
}

function remove_ci_run() {
  local commit="$1"
  local ci_pid="$2"
  for slot in ${!all_ci[@]}
  do
    if [ "${all_ci[$slot]}" == "$commit/$ci_pid" ]; then
      all_ci[$slot]="None/None"
      echo "${all_ci[@]}" > /etc/test-manager/ci-runs.txt
      return
    fi
  done
}

function get_ci_slot() {
  remove_completed_runs
  for slot in ${!all_ci[@]}
  do
    if [ "${all_ci[$slot]}" == "None/None" ]; then
      echo "$slot"
      return
    fi
  done
}

function remove_completed_runs() {
  for slot in ${!all_ci[@]}
  do
    if [ "${all_ci[$slot]}" != "None/None" ]; then
      pid="$(echo ${all_ci[$slot]} | cut -f2 -d/)"
      if [[ "$pid" == "None" || -z "$pid" ]]; then
        continue
      fi
      set +e
      kill -0 $pid 2>/dev/null
      result="$?"
      set -e
      if [ "$result" != "0" ]; then
        commit="$(echo ${all_ci[$slot]} | cut -f1 -d/)"
        remove_ci_run $commit $pid
      fi
      return
    fi
  done
}

args "$@"

if [ -z "$comment" ] ; then
  # cater for case on no public ip, i.e. using private network connection to local IP
  http_code="$(curl -s -w "%{http_code}" -o /dev/null http://169.254.169.254/latest/meta-data/public-ipv4)"
  if [ "$http_code" == "200" ]; then
    export host_name=$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4)
  else
    export host_name=$(curl -s http://169.254.169.254/latest/meta-data/local-ipv4)
  fi
else
  export host_name="https://github.com/paulcarlton-ww/gitops-test-manager/blob/main/README.md#log-access"
fi

source /etc/test-manager/env.sh

all_ci="$(cat /etc/test-manager/ci-runs.txt)"

while true; do 
  # Get PR to test and checkout commit
  getPRs
  sleep 60
done
