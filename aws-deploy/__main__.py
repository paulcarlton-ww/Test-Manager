import pulumi
from pulumi import Output, export, ResourceOptions
import pulumi_aws as aws
import server, networking, roles
import string
import random
import os

def id_generator(size=6, chars=string.ascii_uppercase + string.digits):
    return str(''.join(random.choice(chars) for _ in range(size)))


stack = pulumi.get_stack()
config = pulumi.Config()
server_config = config.require_object("server")
app_config = config.require_object("application")
network_config = config.require_object("networking")
role_config = config.require_object("role")
server_name = server_config.get("name") + "-" + id_generator()
githubtoken_filename = f'/tmp/{server_name}'

try:
    debug = app_config.get("debug") is not None and app_config.get("debug")

    ssh_access = server_config.get("ssh-access") is not None and server_config.get("ssh-access")
    web_access = server_config.get("web-access") is not None and server_config.get("web-access")

    az = network_config.get("az")
    if az is None:
        az = "a"

    region = network_config.get("region")
    if region is None:
        region = os.getenv("AWS_REGION")
    
    if region is None:
        raise Exception("region is required")

    networking = networking.NetworkingComponent(
        "networking",
        networking.NetworkingComponentArgs(
            prefix=server_name,
            cidr_block=network_config.get("vpc-cidr"),
            vpc_id=network_config.get("vpc-id"),
            public_subnet_cidr_block=network_config.get("public-subnet-cidr"),
            private_subnet_cidr_block=network_config.get("private-subnet-cidr"),
            public_subnet_id=network_config.get("public-subnet-id"),
            private_subnet_id=network_config.get("private-subnet-id"),
            ssh_access=ssh_access,
            web_access=web_access,
            az=az,
            region=region
        ),
    )

    config_bucket = aws.s3.Bucket(
        "configuration-bucket",
        acl="private",
        tags={
            "Environment": stack,
            "Name": server_name,
        },
    )

    deployFileName = "./id_rsa"
    if app_config.get("deploy_file") is not None:
        deployFileName = app_config.get("deploy-file")

    deployFile = pulumi.FileAsset(deployFileName)

    deploykey_bucket_object = aws.s3.BucketObject(
        "deploy-key-object", bucket=config_bucket.id, source=deployFile
    )

    github_token_env = app_config.get("test-manager:github-token-env")
    if github_token_env is None:
        github_token_env = "TEST_MANAGER_CI_GITHUB_TOKEN"
    github_token = os.getenv(github_token_env)
    if github_token is None:
        raise Exception("Environmental variable containing GitHub token is required")
        
    with open(githubtoken_filename, 'w+') as f:
        f.write(github_token)

    tokenFile = pulumi.FileAsset(githubtoken_filename)
    githubtoken_bucket_object = aws.s3.BucketObject(
        "github-token-object", bucket=config_bucket.id, source=tokenFile
    )

    testManagerFileName = "./test-manager.sh"
    testManagerFile = pulumi.FileAsset(testManagerFileName)

    testmanager_bucket_object = aws.s3.BucketObject(
        "testmanager-key-object", bucket=config_bucket.id, source=testManagerFile
    )

    iam_role = None
    iam_role_name = role_config.get("iam-role-name")
    if iam_role_name is None:
        permissions_boundary_arn = role_config.get("permissions_boundary")
        policies = role_config.get("policies")
        if policies is None:
            raise pulumi.ConfigMissingError("test-manager:policies")

        component_roles = [config_bucket]
        roles = roles.RolesComponent(
            "roles",
            roles.RolesComponentArgs(
                server_name, *component_roles, policies, permissions_boundary_arn=permissions_boundary_arn
            ),
        )
        iam_role = roles.base_instance_role
    else:
        role_info = aws.iam.get_role(name=iam_role_name)
        iam_role = aws.iam.Role.get("iam_role", role_info.id)

    proxy_http=None
    proxy_https=None
    no_proxy=None
    if server_config.get("proxy-setup") is not None:
        proxy_http=server_config["proxy-setup"].get("http-proxy"),
        proxy_https=server_config["proxy-setup"].get("https-proxy"),
        no_proxy=server_config["proxy-setup"].get("no-proxy"),

    server_args = {
        "deploykey_s3_url": Output.concat(
                        "s3://",
                        deploykey_bucket_object.bucket,
                        "/",
                        deploykey_bucket_object.key,
                    ),
        "githubtoken_s3_url": Output.concat(
                        "s3://",
                        githubtoken_bucket_object.bucket,
                        "/",
                        githubtoken_bucket_object.key,
                    ),
        "testmanager_s3_url": Output.concat(
                        "s3://",
                        testmanager_bucket_object.bucket,
                        "/",
                        testmanager_bucket_object.key,
                    ),
        "private_subnet": networking.private_subnet,
        "vpc_security_group_ids": [networking.tm_sg.id],
        "ami_id": server_config.get("ami-id"),
        "iam_role": iam_role,
        "ssh_key_name": server_config.get("ssh-key-name"),
        "private_ips": [server_config.get("ip-address")],
        "proxy_http": proxy_http,
        "proxy_https": proxy_https,
        "no_proxy": no_proxy,
        "github_org_repo": app_config.get("github-org-repo"),
        "ci_script": app_config.get("ci-script"),
        "stack_name": stack,
        "debug": debug,
        "tags": {
            "Name": server_name,
        },
        "region": region,
        "ssh_access": ssh_access,
        "web_access": web_access
    }

    if ssh_access or web_access:
        server_args["public_subnet"] = networking.public_subnet

    root_volume_size = server_config.get("root-vol-size")
    if root_volume_size is not None:
        server_args["root_volume_size"] = root_volume_size

    root_volume_type = server_config.get("root-vol-type")
    if root_volume_type is not None:
        server_args["root_volume_type"] = root_volume_type

    instance_type = server_config.get("instance-type")
    if instance_type is not None:
        server_args["instance_type"] = instance_type

    user_data_file = app_config.get("user-data-file")
    if user_data_file is not None:
        server_args["user_data_file"] = user_data_file

    server = server.ServerComponent(server_name, **server_args)

    pulumi.export('instance', server.instance.id)
finally:
    if os.path.exists(githubtoken_filename):
        print(f'rm {githubtoken_filename}')
