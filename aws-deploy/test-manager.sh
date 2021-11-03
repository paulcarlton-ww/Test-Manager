
#!/bin/bash

# Utility for running github repo ci testing script against PRs
# Version: 1.0
# Author: Paul Carlton (mailto:paul.carlton@weave.works)

function usage()
{
    echo "usage ${0} [--debug]"
    echo "This script will look for new PRs and run the configured ci script against the PR branch"
}

function args() {
  debug=""
  arg_list=( "$@" )
  arg_count=${#arg_list[@]}
  arg_index=0
  while (( arg_index < arg_count )); do
    case "${arg_list[${arg_index}]}" in
          "--debug") set -x; debug="--debug";;
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

function run_ci() {
  mkdir -p /var/www/$pr
  set_check_pending
  echo "Execute CI script: $CI_SCRIPT"
  echo "PWD: $PWD"
  $CI_SCRIPT > /var/www/$pr/ci-output.log 2>&1
  result=$?
  commentPR /var/www/$pr/ci-output.log
  set_check_completed $result
}

function clone_repo() {
  REPO=$(echo $GITHUB_ORG_REPO | cut -f2 -d/)
  if [ -d "$REPO" ]; then
    rm -rf $REPO
  fi
  git clone https://$GITHUB_TOKEN@github.com/$GITHUB_ORG_REPO.git
  cd $REPO
}

function getPR() {
  for pr in $(curl -s -H "Authorization: token $GITHUB_TOKEN" https://api.github.com/repos/$GITHUB_ORG_REPO/pulls | jq -r '.[].number')
  do
    processPR $pr
  done
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
    | jq -r '.[] | select( .context == "ci-ww-cx")' | jq -r '.state + "/" + .updated_at' | sort -k 2 -t/ | tail -1 | cut -f1 -d/)
  if [ -z "$status" ]; then
    git fetch --all
    git checkout $commit_sha
    run_ci
    sleep_time=1
  else
    sleep_time=60
  fi
}

function commentPR() {
  data_file=$1
  data=$(sed -e 's/\"/\\\"/g' $data_file | awk '{printf "%s\\n", $0}')
  curl -v -X POST -H "Authorization: token $GITHUB_TOKEN" -H "Accept: application/vnd.github.v3+json" https://api.github.com/repos/$GITHUB_ORG_REPO/issues/$pr/comments \
    -d "{\"state\":\"COMMENTED\", \"body\": \"$data\"}"
}

function approvePR() {
  curl -v -X POST -H "Authorization: token $GITHUB_TOKEN" -H "Accept: application/vnd.github.v3+json" https://api.github.com/repos/$GITHUB_ORG_REPO/pulls/$pr/reviews \
    -d '{"event":"APPROVE"}'
}

function set_check_pending() {
  curl -v -X POST -H "Authorization: token $GITHUB_TOKEN" -H "Accept: application/vnd.github.v3+json" https://api.github.com/repos/$GITHUB_ORG_REPO/statuses/$commit_sha \
    -d '{"context":"ci-ww-cx","description": "ci run started","state":"pending", "target_url": "http://$hostname/$pr/ci-output.log"}'
}

function set_check_completed() {
  local result=$1
  if [ "$result" == "0" ]; then
    curl -v -X POST -H "Authorization: token $GITHUB_TOKEN" -H "Accept: application/vnd.github.v3+json" https://api.github.com/repos/$GITHUB_ORG_REPO/statuses/$commit_sha \
      -d '{"context":"ci-ww-cx","description": "ci run completed successfully","state":"success", "target_url": "http://$hostname/$pr/ci-output.log"}'
      approvePR
  else
    curl -v -X POST -H "Authorization: token $GITHUB_TOKEN" -H "Accept: application/vnd.github.v3+json" https://api.github.com/repos/$GITHUB_ORG_REPO/statuses/$commit_sha \
      -d '{"context":"ci-ww-cx","description": "ci run failed","state":"failure", "target_url": "http://$hostname/$pr/ci-output.log"}'
  fi
}

args "$@"

hostname=$(curl http://169.254.169.254/latest/meta-data/public-ipv4)
TMPDIR=$(mktemp -d)
cd $TMPDIR
source /etc/test-manager/env.sh
clone_repo

while true; do 
  source /etc/test-manager/env.sh
  # Get PR to test and checkout commit
  getPR
  sleep $sleep_time
done
