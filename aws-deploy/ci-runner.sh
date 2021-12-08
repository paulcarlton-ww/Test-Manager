#!/bin/bash

# Utility for running github repo ci testing script against PRs
# Version: 1.0
# Author: Paul Carlton (mailto:paul.carlton@weave.works)

set -xeuo pipefail

tempfiles=( )
cleanup() {
  rm -f "${tempfiles[@]}"
}
trap cleanup 0

error() {
  local parent_lineno="$1"
  local message="$2"
  local code="${3:-1}"
  if [[ -n "$message" ]] ; then
    echo "Error on or near line ${parent_lineno}: ${message}; exiting with status ${code}"
  else
    echo "Error on or near line ${parent_lineno}; exiting with status ${code}"
  fi
  set_check_completed 1
  exit "${code}"
}
trap 'error ${LINENO}' ERR

function usage()
{
    echo "usage ${0} [--debug] [--comment] --pull-request <pr number> --commit-sha <commit sha>"
    echo "This script will look for new PRs and run the configured ci script against the PR branch"
    echo "--comment option causes comments to be written to PR containing test log"
    echo "--pull-request is the pull request number"
    echo "--commit-sha is the commit sha"
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
          "--pull-request") (( arg_index+=1 ));pr="${arg_list[${arg_index}]}";;
          "--commit-sha") (( arg_index+=1 ));commit_sha="${arg_list[${arg_index}]}";;
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
  clone_repo
  git checkout $commit_sha
  if [ -n "$comment" ] ; then
    log_file=/var/log/pr$pr-ci-output.log
  else
    mkdir -p /var/www/html/pr$pr
    log_path="/pr$pr/ci-output.log"
    log_file=/var/www/html$log_path
  fi
  if [ -f "$CI_SCRIPT" ]; then
    set_check_running
    echo "Execute CI script: $PWD/$CI_SCRIPT"
    $CI_SCRIPT > $log_file 2>&1
    result=$?
    if [ -n "$comment" ] ; then
      commentPR $log_file
    fi
    set_check_completed $result
  else
    echo "no $CI_SCRIPT file found in PR" > $log_file
    set_check_completed 1
  fi
  cd
  rm -rf $TMPDIR
}

function clone_repo() {
  TMPDIR=$(mktemp -d)
  tempfiles+=( "$TMPDIR" )
  cd $TMPDIR
  REPO=$(echo $GITHUB_ORG_REPO | cut -f2 -d/)
  if [ -d "$REPO" ]; then
    rm -rf $REPO
  fi
  git lfs install --skip-repo
  git clone https://$GITHUB_TOKEN@github.com/$GITHUB_ORG_REPO.git
  cd $REPO
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

function set_check_running() {
  curl -v -X POST -H "Authorization: token $GITHUB_TOKEN" -H "Accept: application/vnd.github.v3+json" https://api.github.com/repos/$GITHUB_ORG_REPO/statuses/$commit_sha \
    -d "{\"context\":\"$CI_ID\",\"description\": \"ci run started\",\"state\":\"pending\", \"target_url\": \"http://$host_name$log_path\"}"
}

function set_check_completed() {
  local result=$1
  if [ "$result" == "0" ]; then
    curl -v -X POST -H "Authorization: token $GITHUB_TOKEN" -H "Accept: application/vnd.github.v3+json" https://api.github.com/repos/$GITHUB_ORG_REPO/statuses/$commit_sha \
      -d "{\"context\":\"$CI_ID\",\"description\": \"ci run completed successfully\",\"state\":\"success\", \"target_url\": \"http://$host_name$log_path\"}"
      approvePR
  else
    curl -v -X POST -H "Authorization: token $GITHUB_TOKEN" -H "Accept: application/vnd.github.v3+json" https://api.github.com/repos/$GITHUB_ORG_REPO/statuses/$commit_sha \
      -d "{\"context\":\"$CI_ID\",\"description\": \"ci run failed\",\"state\":\"failure\", \"target_url\": \"http://$host_name$log_path\"}"
  fi
}

args "$@"

log_path=""

# Set AWS creds

TOKEN=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
curl -s -H "X-aws-ec2-metadata-token: $TOKEN" -v http://169.254.169.254/latest/meta-data/iam/security-credentials/$INSTANCE_ROLE > $HOME/iam.json

export AWS_ACCESS_KEY_ID=$(jq -r '."AccessKeyId"' $HOME/iam.json)
export AWS_SECRET_ACCESS_KEY=$(jq -r '."SecretAccessKey"' $HOME/iam.json)
export AWS_SESSION_TOKEN=$(jq -r '."Token"' $HOME/iam.json)

run_ci
