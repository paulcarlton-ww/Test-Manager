# Test-Manager

Test Manager deploys a EC2 instance in an AWS account which will monitor a configured GitHub repository and run a configured script for each non draft Pull Request. It is designed to be used to perform continuous integration (CI) testing of pull requests and will report the result of the script execution as a check status. It does not need a GitHub action or secrets to execute the test script.

To deploy the test manager in an AWS account to do CI testing for a repository you must provide a GitHub token with write access to the repository under test.