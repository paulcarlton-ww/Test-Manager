#!/usr/bin/env bash

debug_opt=""
if [ "{debug}" == "True" ]; then
    set -x
    debug_opt="--debug"
fi

export HOME=/home/ec2-user

PreflightSteps () {{
    amazon-linux-extras install epel -y

    echo "Installing proxy"

    echo "{proxy_http}"
    echo "{proxy_https}"
    echo "{no_proxy}"

    mkdir -p /etc/test-manager

    if [ "{proxy_http}" != "None" ]; then
        export http_proxy="{proxy_http}"
        export HTTP_PROXY="{proxy_http}"
        echo "export HTTP_PROXY={proxy_http}" >> /etc/test-manager/env.sh
        echo "export http_proxy={proxy_http}" >> /etc/test-manager/env.sh
        echo "proxy={proxy_http}" >> /etc/yum.conf
    fi

    if [ "{proxy_https}" != "None" ]; then
        export https_proxy="{proxy_https}"
        export HTTPS_PROXY="{proxy_https}"
        echo "export HTTPS_PROXY={proxy_https}" >> /etc/test-manager/env.sh
        echo "export https_proxy={proxy_https}" >> /etc/test-manager/env.sh
        export curl_proxy_opt="--proxy $https_proxy"
        echo "export curl_proxy_opt=\"--proxy $https_proxy\"" >> /etc/test-manager/env.sh
    fi

    if [ "{no_proxy}" != "None" ]; then
        export no_proxy="{no_proxy}"
        export NO_PROXY="{no_proxy}"
        echo "export NO_PROXY={no_proxy}" >> /etc/test-manager/env.sh
        echo "export no_proxy={no_proxy}" >> /etc/test-manager/env.sh
    fi

    echo "Updating system packages & installing required utilities"
    yum-config-manager --enable epel
    yum update -y
    yum install -y jq curl unzip git git-lfs
    curl $curl_proxy_opt "https://s3.amazonaws.com/session-manager-downloads/plugin/latest/linux_64bit/session-manager-plugin.rpm" -o "session-manager-plugin.rpm"
    sudo yum install -y session-manager-plugin.rpm

    echo "Installing AWS CLI"
    TMPDIR=$(mktemp -d)
    cd $TMPDIR
    echo "Downloading AWS CLI"
    curl $curl_proxy_opt "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
    unzip -q awscliv2.zip
    ./aws/install

    export AWS_REGION={region}
    echo "Installing SSM Agent"
    yum install -y https://s3.$AWS_REGION.amazonaws.com/amazon-ssm-$AWS_REGION/latest/linux_amd64/amazon-ssm-agent.rpm
    systemctl enable amazon-ssm-agent
    systemctl start amazon-ssm-agent
    systemctl status amazon-ssm-agent
}}

SetupWebServer () {{
    echo "Setup WebServer"
    amazon-linux-extras install -y lamp-mariadb10.2-php7.2 php7.2
    yum install -y httpd
    systemctl start httpd
    systemctl enable httpd
    usermod -a -G apache ec2-user
    chown -R ec2-user:apache /var/www
    chmod -R 775 /var/www
}}

RetrieveGithubToken () {{
    echo "Retrieving Github Token"
    mkdir -p /etc/test-manager
    aws s3 cp {githubtoken_s3_url} /etc/test-manager/github-token
}}

DeployTestManager () {{
    echo "Deploying Test Manager"
    aws s3 cp {testrunner_s3_url} /tmp/tests-runner.sh
    mv /tmp/tests-runner.sh /usr/bin
    chmod 755 /usr/bin/tests-runner.sh
    aws s3 cp {testmanager_s3_url} /tmp/test-manager.sh
    mv /tmp/test-manager.sh /usr/bin
    chmod 755 /usr/bin/test-manager.sh
    aws s3 cp {cirunner_s3_url} /tmp/ci-runner.sh
    mv /tmp/ci-runner.sh /usr/bin
    chmod 755 /usr/bin/ci-runner.sh
}}

PreflightSteps

comment_opt=""
if [ "{web_access}" == "True" ]; then
    SetupWebServer
else
    comment_opt="--comment"
fi

RetrieveGithubToken
DeployTestManager

echo "export GITHUB_ORG_REPO={github_org_repo}" >> /etc/test-manager/env.sh
echo "export CI_SCRIPT={ci_script}" >> /etc/test-manager/env.sh
echo "export CI_ID={ci_id}" >> /etc/test-manager/env.sh
echo "export CONCURRENT_CI_RUNS={concurrent_ci_runs}" >> /etc/test-manager/env.sh
echo "export GITHUB_TOKEN=$(cat /etc/test-manager/github-token)" >> /etc/test-manager/env.sh
echo "export INSTANCE_ROLE={instance_role}" >> /etc/test-manager/env.sh
echo "export AWS_REGION={region}" >> /etc/test-manager/env.sh

# Run test manager...
source /etc/test-manager/env.sh
counter=1
unused="None/None"
init=$unused
until [ $counter -eq $CONCURRENT_CI_RUNS ]
do
init="$init $unused"
((counter++))
done

echo "$init" > /etc/test-manager/ci-runs.txt
chown ec2-user:ec2-user /etc/test-manager/ci-runs.txt

nohup sudo -E -u ec2-user tests-runner.sh $debug_opt $comment_opt >/var/log/test-manager.log 2>&1 &
