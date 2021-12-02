
#!/bin/bash

# Utility for running github repo ci testing script against PRs
# Version: 1.0
# Author: Paul Carlton (mailto:paul.carlton@weave.works)

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
  for pr in $(curl -s -H "Authorization: token $GITHUB_TOKEN" https://api.github.com/repos/$GITHUB_ORG_REPO/pulls | jq -r '.[].number')
  do
    processPR $pr
  done
}

function set_check_pending() {
  curl -v -X POST -H "Authorization: token $GITHUB_TOKEN" -H "Accept: application/vnd.github.v3+json" https://api.github.com/repos/$GITHUB_ORG_REPO/statuses/$commit_sha \
    -d "{\"context\":\"$CI_CD\",\"description\": \"ci run pending\",\"state\":\"pending\", \"target_url\": \"http://$host_name/pr$pr/ci-output.log\"}"
}

function processPR() {
  local draft=$(curl -s -H "Authorization: token $GITHUB_TOKEN" https://api.github.com/repos/$GITHUB_ORG_REPO/pulls/$pr | jq -r '.draft')
  if [ "$draft" == "true" ]; then
    echo "skipping draft PR: #$pr"
    return
  fi
  local branch=$(curl -s -H "Authorization: token $GITHUB_TOKEN" https://api.github.com/repos/$GITHUB_ORG_REPO/pulls/$pr | jq -r '.head.ref')
  commit_sha=$(curl -s -H "Authorization: token $GITHUB_TOKEN" https://api.github.com/repos/$GITHUB_ORG_REPO/commits/$branch | jq -r '.sha')
  status=$(curl -s -H "Authorization: token $GITHUB_TOKEN" -H "Accept: application/vnd.github.v3+json" https://api.github.com/repos/$GITHUB_ORG_REPO/statuses/$commit_sha \
    | jq -r --arg CI_ID "$CI_ID" '.[] | select( .context==$CI_ID)' | sort -k 2 -t/ | tail -1 | cut -f1 -d/)
  if [[ -z "$status" ]]; then
    set_check_pending
    # ToDo: get parent of commit and cancel any active ci runs.
    # Check if max concurrent ci runs are active.
    nohup ci-runner.sh $debug $comment --pull-request $pr --commit-sha $commit_sha >/var/log/ci-$branch-$commit_sha.log 2>&1 &
    ci_pid=$!
  fi
}

args "$@"

if [ -n "$comment" ] ; then
  export host_name=$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4)
else
  export hostname="https://github.com/paulcarlton-ww/gitops-test-manager/blob/main/README.md#log-access"
fi
source /etc/test-manager/env.sh

all_ci=($(cat etc/test-manager/ci-runs.txt))

while true; do 
  # Get PR to test and checkout commit
  getPRs
  sleep 10
done
