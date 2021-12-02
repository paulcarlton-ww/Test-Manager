#!/bin/bash

# Utility for running github repo ci testing script against PRs
# Version: 1.0
# Author: Paul Carlton (mailto:paul.carlton@weave.works)

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
  set_check_pending
  echo "Execute CI script: $PWD/$CI_SCRIPT"
  $CI_SCRIPT > $log_file 2>&1
  result=$?
  if [ -n "$comment" ] ; then
    commentPR $log_file
  fi
  set_check_completed $result
  cd
  rm -rf $TMPDIR
}

function clone_repo() {
  TMPDIR=$(mktemp -d)
  cd $TMPDIR
  REPO=$(echo $GITHUB_ORG_REPO | cut -f2 -d/)
  if [ -d "$REPO" ]; then
    rm -rf $REPO
  fi
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
    -d "{\"context\":\"$CI_CD\",\"description\": \"ci run started\",\"state\":\"pending\", \"target_url\": \"http://$host_name$log_path\"}"
}

function set_check_cancelled() {
  curl -v -X POST -H "Authorization: token $GITHUB_TOKEN" -H "Accept: application/vnd.github.v3+json" https://api.github.com/repos/$GITHUB_ORG_REPO/statuses/$commit_sha \
    -d "{\"context\":\"$CI_CD\",\"description\": \"ci run cancelled\",\"state\":\"error\", \"target_url\": \"http://$host_name$log_path\"}"
}

function set_check_completed() {
  local result=$1
  if [ "$result" == "0" ]; then
    curl -v -X POST -H "Authorization: token $GITHUB_TOKEN" -H "Accept: application/vnd.github.v3+json" https://api.github.com/repos/$GITHUB_ORG_REPO/statuses/$commit_sha \
      -d "{\"context\":\"$CI_CD\",\"description\": \"ci run completed successfully\",\"state\":\"success\", \"target_url\": \"http://$host_name$log_path\"}"
      approvePR
  else
    curl -v -X POST -H "Authorization: token $GITHUB_TOKEN" -H "Accept: application/vnd.github.v3+json" https://api.github.com/repos/$GITHUB_ORG_REPO/statuses/$commit_sha \
      -d "{\"context\":\"$CI_CD\",\"description\": \"ci run failed\",\"state\":\"failure\", \"target_url\": \"http://$host_name$log_path\"}"
  fi
}

args "$@"

log_path=""

run_ci
