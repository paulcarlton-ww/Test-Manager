# Test-Manager

Test Manager deploys a EC2 instance in an AWS account which will monitor a configured GitHub repository and run a configured script for each non draft Pull Request. It is designed to be used to perform continuous integration (CI) testing of pull requests and will report the result of the script execution as a check status. It does not need a GitHub action or secrets to execute the test script.

To deploy the test manager in an AWS account in order to do CI testing for a repository you must provide a GitHub token with write access to the repository under test. You also need to provide the GitHub repository name and the path to the script to be executed. The GitHub token is provided via an environmental variable `TEST_MANAGER_CI_GITHUB_TOKEN` and the other information is specficed via a yaml file. See [Pulumi.sample.yaml](aws-deploy/Pulumi.sample.yaml) for an example.

The following environmental variables are avaialable to the CI testing script executed by the test manager:

| Variable | Description |
| --- | --- |
| `PR_NUM` | Pull Request number |
| `CI_ID` | Name of this CI tester |
| `GITHUB_TOKEN` | GitHub token used to update pull request status |
| `AWS_REGION` | AWS Region |

## Setup

Install python3, pip, [Pulumi](https://www.pulumi.com/docs/get-started/install/) and [AWS CLI version 2](https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2-mac.html).

Clone this repository and deploy the python code in a virtualenv, e.g.

    cd <path to clone of directory>
    export PATH=$PATH:$PWD/bin
    cd aws-deploy
    pip install virtualenv
    virtualenv venv
    source venv/bin/activate
    pip install -r requirements.txt

## Deploy

To deploy a test manager you need AWS credentials for and Admin user in the target AWS account.

Create an S3 bucket to use for the pulumi stack:

    create-state-bucket.sh <bucket name> <AWS region> <stack name>

e.g.

    create-state-bucket.sh aws-github-test-manager $AWS_REGION aws-github

Then copy the sample yaml file to `Pulumi.<stack-name>.yaml and edit it to reflect the requirements for the specific respository, i.e.

    cd aws-deploy
    cp Pulumi.sample.yaml Pulumi.aws-github.yaml

When ready to create the test manager, source your AWS credentials for the target account and deploy the test manager:

    export PULUMI_CONFIG_PASSPHRASE=""    
    pulumi --non-interactive login s3://aws-github-test-manager
    pulumi --non-interactive up  --yes --stack aws-github

## Log Access

If the EC2 instance running the CI checks has not been deployed with web access enabled then it is not possible to view the CI check log file.
