#!/usr/bin/env bash

if [ "{debug}" == "True" ]; then
    set -x
    env | sort
    whoami
    debug_opt="--debug"
fi

export HOME=/home/ec2-user

PreflightSteps () {{
    echo "Installing proxy"

    echo "{proxy_http}"
    echo "{proxy_https}"
    echo "{no_proxy}"

    if [ "{proxy_http}" != "None" ]; then
        export http_proxy="{proxy_http}"
        export HTTP_PROXY="{proxy_http}"
    fi

    if [ "{proxy_https}" != "None" ]; then
        export https_proxy="{proxy_https}"
        export HTTPS_PROXY="{proxy_https}"
    fi

    if [ "{no_proxy}" != "None" ]; then
        export no_proxy="{no_proxy}"
        export NO_PROXY="{no_proxy}" 
    fi

    echo "Updating system packages & installing Zip"
    yum update -y
    yum install -y jq yq curl unzip python3-pip python3-virtualenv git
    curl "https://s3.amazonaws.com/session-manager-downloads/plugin/latest/linux_64bit/session-manager-plugin.rpm" -o "session-manager-plugin.rpm"
    sudo yum install -y session-manager-plugin.rpm
    curl -fsSL https://get.pulumi.com | sh
    export PATH=$PATH:~/.pulumi/bin

    echo "Installing AWS CLI"
    TMPDIR=$(mktemp -d)
    cd $TMPDIR
    echo "Downloading AWS CLI"
    curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
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
    chmod -R 2775 /var/www
}}

RetrieveDeployKey () {{
    echo "Retrieving Deploy Key"
    mkdir -p /etc/test-manager
    aws s3 cp {deploykey_s3_url} /etc/test-manager/deploy-key
    chmod 600 /etc/test-manager/deploy-key
}}

RetrieveGithubToken () {{
    echo "Retrieving Github Token"
    mkdir -p /etc/test-manager
    aws s3 cp {githubtoken_s3_url} /etc/test-manager/github-token
}}

DeployTestManager () {{
    echo "Deploying Test Manager"
    aws s3 cp {testmanager_s3_url} /tmp/test-manager.sh
    mv /tmp/test-manager.sh /usr/bin
    chmod 755 /usr/bin/test-manager.sh
}}

PreflightSteps
SetupWebServer
RetrieveDeployKey
RetrieveGithubToken
DeployTestManager

echo "export GITHUB_ORG_REPO={github_org_repo}" > /etc/test-manager/env.sh
echo "export CI_SCRIPT={ci_script}" >> /etc/test-manager/env.sh
echo "export GITHUB_TOKEN=$(cat /etc/test-manager/github-token)" >> /etc/test-manager/env.sh
mkdir -p $HOME/.ssh
cp /etc/test-manager/deploy-key $HOME/.ssh/id_rsa
ssh-keyscan -H github.com >> $HOME/.ssh/known_hosts

# Run test manager...
nohup test-manager.sh $debug_opt >/var/log/test-manager.log 2>&1 &
