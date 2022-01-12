import pulumi
import pulumi_aws as aws
import json


class RolesComponentArgs:
    def __init__(self, configS3Bucket, policies, permissions_boundary_arn=None):
        self.configS3Bucket = configS3Bucket
        self.policies = policies
        self.permissions_boundary_arn = permissions_boundary_arn


class RolesComponent(pulumi.ComponentResource):
    def __init__(self, name, args: RolesComponentArgs, opts=None):
        super().__init__("pkg:index:RolesComponent", name, None, opts)
        inline_policies = [
                aws.iam.RoleInlinePolicyArgs(
                    name="configS3Bucket",
                    policy=args.configS3Bucket.arn.apply(
                        lambda bucket_arn: json.dumps(
                            {
                                "Version": "2012-10-17",
                                "Statement": [
                                    {
                                        "Action": ["s3:GetObject"],
                                        "Effect": "Allow",
                                        "Resource": f"{bucket_arn}/*",
                                    },
                                    {
                                        "Action": ["s3:ListBucket"],
                                        "Effect": "Allow",
                                        "Resource": bucket_arn,
                                    },
                                    {
                                        "Action": ["s3:HeadBucket"],
                                        "Effect": "Allow",
                                        "Resource": [
                                            bucket_arn,
                                            f"{bucket_arn}/*"
                                        ],
                                    },
                                ],
                            }
                        ),
                    ),
                ),
            ]

        self.base_instance_role = aws.iam.Role(
            "base-instance-role",
            assume_role_policy=json.dumps(
                {
                    "Version": "2012-10-17",
                    "Statement": [
                        {
                            "Action": "sts:AssumeRole",
                            "Effect": "Allow",
                            "Principal": {"Service": "ec2.amazonaws.com"},
                        }
                    ],
                }
            ),
            permissions_boundary=args.permissions_boundary_arn,
            inline_policies=inline_policies,
            managed_policy_arns=args.policies,
            opts=pulumi.ResourceOptions(parent=self),
        )
