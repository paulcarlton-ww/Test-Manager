import pulumi
import pulumi_aws as aws
from pulumi import Output, ResourceOptions
from pulumi_aws.ec2 import subnet
from pulumi_aws.iam import ssh_key

class ServerComponent(pulumi.ComponentResource):
    def __init__(self, name: str,
        private_subnet=None,
        public_subnet=None,
        vpc_security_group_ids:str=None,
        ami_id:str=None,
        iam_role:str=None,
        ssh_key_name=None,
        private_ips=None,
        root_volume_size=40,
        root_volume_type="gp2",
        instance_type="t2.micro",
        tags=None,
        proxy_http=None,
        proxy_https=None,
        no_proxy=None,
        user_data_file="./server_user_data.sh",
        deploykey_s3_url=None,
        githubtoken_s3_url=None,
        testmanager_s3_url=None,
        github_org_repo=None,
        ci_script=None,
        stack_name=None,
        debug=False,
        region=None,
        ssh_access=False,
        web_access=False,
        opts=None):
        super().__init__("pkg:index:ServerComponent", name, None, opts)
        self.name = name
        self.public_subnet = public_subnet
        self.private_subnet = private_subnet
        self.vpc_security_group_ids = vpc_security_group_ids
        self.ami_id = ami_id
        self.iam_role = iam_role
        self.ssh_key_name = ssh_key_name
        self.private_ips = private_ips
        self.root_volume_size = root_volume_size
        self.root_volume_type = root_volume_type
        self.instance_type = instance_type
        self.tags = tags
        self.user_data_file = user_data_file
        self.proxy_http = proxy_http
        self.proxy_https = proxy_https
        self.no_proxy = no_proxy
        self.deploykey_s3_url = deploykey_s3_url
        self.githubtoken_s3_url= githubtoken_s3_url
        self.testmanager_s3_url= testmanager_s3_url
        self.github_org_repo = github_org_repo
        self.ci_script = ci_script
        self.stack_name = stack_name
        self.debug = debug
        self.region = region
        self.web_access = web_access
        self.ssh_access = ssh_access

        if self.ami_id is None:
            self.ami = self.get_ami()
        else:
            self.ami = aws.ec2.Ami.get("ami",id=self.ami_id)

        instance_profile = aws.iam.InstanceProfile(
            f"instance-profile-{name}",
            role=self.iam_role,
            tags={"Name": name},
            opts=pulumi.ResourceOptions(parent=self, depends_on=[self.iam_role]),
        )

        depends_on=[instance_profile]

        subnet = self.private_subnet
        if ssh_access or web_access:
            subnet = self.public_subnet
        
        depends_on.append(subnet)

        kwargs = {
            "iam_instance_profile": instance_profile,
            "instance_type": self.instance_type, 
            "ami": self.ami.id,   
            "user_data": self.get_user_data(),
            "root_block_device": aws.ec2.InstanceRootBlockDeviceArgs(
                volume_type=self.root_volume_type,
                volume_size=self.root_volume_size,
                encrypted=True,
            ),
            "subnet_id": subnet.id,
            "vpc_security_group_ids": self.vpc_security_group_ids,
            "opts": ResourceOptions(depends_on=depends_on, parent=self)
        }

        if self.ssh_key_name is not None:
            kwargs["key_name"] = self.ssh_key_name

        if self.tags is not None:
            kwargs["tags"] = self.tags

        self.instance = aws.ec2.Instance(name, **kwargs)

    def get_ami(self):
        return aws.ec2.get_ami(
            most_recent="true",
            owners=[137112412989],
                  filters=[{"name":"name","values":["amzn2-ami-hvm-*"]}])

    def get_user_data(self):

        return Output.all(
            self.proxy_http,
            self.proxy_https,
            self.no_proxy,
            self.debug,
            self.github_org_repo,
            self.ci_script,
            self.deploykey_s3_url,
            self.githubtoken_s3_url,
            self.testmanager_s3_url,
            self.region
        ).apply(
            lambda args: (
                open(self.user_data_file)
                .read()
                .format(
                    proxy_http=args[0],
                    proxy_https=args[1],
                    no_proxy=args[2],
                    debug=args[3],
                    github_org_repo=args[4],
                    ci_script=args[5],
                    deploykey_s3_url=args[6],
                    githubtoken_s3_url=args[7],
                    testmanager_s3_url=args[8],
                    region=args[9]
                )
            )
        )