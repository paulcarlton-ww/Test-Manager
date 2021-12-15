import pulumi
import pulumi_aws as aws


class NetworkingComponentArgs:
    def __init__(
        self,
        prefix,
        vpc_id=None,
        private_subnet_id=None,
        public_subnet_id=None,
        cidr_block="10.0.0.0/16",
        public_subnet_cidr_block=None,
        private_subnet_cidr_block="10.0.0.0/24",
        ssh_access=False,
        web_access=False,
        az='a',
        region=None
    ):
        self.prefix = prefix.replace('_', '-')
        self.cidr_block = cidr_block
        self.public_subnet_cidr_block = public_subnet_cidr_block
        self.private_subnet_cidr_block = private_subnet_cidr_block
        self.vpc_id = vpc_id
        self.private_subnet_id = private_subnet_id
        self.public_subnet_id = public_subnet_id
        self.create_vpc = self.vpc_id is None
        self.ssh_access = ssh_access
        self.web_access = web_access
        self.region = region
        self.az = f'{region}{az}'

class NetworkingComponent(pulumi.ComponentResource):
    def __init__(self, name, args: NetworkingComponentArgs, opts=None):
        super().__init__("pkg:index:NetworkingComponent", name, None, opts)
        self.vpc = None
        self.igw = None
        self.route_table = None

        if args.create_vpc:
            self.vpc = aws.ec2.Vpc(
                "vpc",
                cidr_block=args.cidr_block,
                tags={"Name": args.prefix},
                opts=pulumi.ResourceOptions(parent=self),
            )

            self.igw = aws.ec2.InternetGateway(
                "igw", vpc_id=self.vpc.id, 
                tags={"Name": args.prefix},
                opts=pulumi.ResourceOptions(parent=self)
            )

            public_route_table = aws.ec2.RouteTable(
                "route_table",
                vpc_id=self.vpc.id,
                tags={"Name": args.prefix},
                routes=[
                    aws.ec2.RouteTableRouteArgs(
                        cidr_block="0.0.0.0/0",
                        gateway_id=self.igw.id,
                    )
                ],
                opts=pulumi.ResourceOptions(parent=self),
            )

            self.public_subnet = aws.ec2.Subnet(
                f"public-{args.prefix}",
                vpc_id=self.vpc.id,
                map_public_ip_on_launch=True,
                cidr_block=args.public_subnet_cidr_block,
                availability_zone=args.az,
                tags={"Name": f"public-{args.prefix}"},
                opts=pulumi.ResourceOptions(parent=self),
            )
            aws.ec2.RouteTableAssociation(
                f"rt-association-public-{args.az}-{args.prefix}",
                route_table_id=public_route_table.id,
                subnet_id=self.public_subnet.id,
                opts=pulumi.ResourceOptions(parent=self),
            )

            eip = aws.ec2.Eip(
                f"nat-gw-eip-{args.az}-{args.prefix}",
                vpc=True,
                tags={"Name": args.prefix},
                opts=pulumi.ResourceOptions(parent=self),
            )

            self.nat_gws = aws.ec2.NatGateway(
                f"nat-gw-{args.az}-{args.prefix}",
                subnet_id=self.public_subnet.id,
                allocation_id=eip.id,
                tags={"Name": args.prefix},
                opts=pulumi.ResourceOptions(
                    depends_on=[self.public_subnet],
                    parent=self),
            )

            self.private_subnet = aws.ec2.Subnet(
                f"private-{args.az}-{args.prefix}",
                vpc_id=self.vpc.id,
                map_public_ip_on_launch=False,
                cidr_block=args.private_subnet_cidr_block,
                availability_zone=args.az,
                tags={"Name": f"private-{args.az}-{args.prefix}"},
                opts=pulumi.ResourceOptions(parent=self),
            )

            private_route_table = aws.ec2.RouteTable(
                f"private-route-table-{args.az}-{args.prefix}",
                vpc_id=self.vpc.id,
                routes=[
                    aws.ec2.RouteTableRouteArgs(
                        cidr_block="0.0.0.0/0",
                        nat_gateway_id=self.nat_gws.id,
                    )
                ],
                tags={"Name": args.prefix},
                opts=pulumi.ResourceOptions(parent=self),
            )

            aws.ec2.RouteTableAssociation(
                f"rt-association-private-{args.az}-{args.prefix}",
                route_table_id=private_route_table.id,
                subnet_id=self.private_subnet.id,
                opts=pulumi.ResourceOptions(parent=self),
            )
        else:
            self.vpc = aws.ec2.Vpc.get(
                "vpc",
                id=args.vpc_id,
                opts=pulumi.ResourceOptions(parent=self),
            )

            self.private_subnet = aws.ec2.Subnet.get(
                f"private-subnet-{self.prefix}",
                id=self.private_subnet_id,
                opts=pulumi.ResourceOptions(parent=self),
            )

            self.public_subnet = aws.ec2.Subnet.get(
                f"public-subnet-{self.prefix}",
                id=self.public_subnet_id,
                opts=pulumi.ResourceOptions(parent=self),
            )

        ingress = []
        if args.web_access:
            ingress = [
                {
                    "protocol": "tcp",
                    "from_port": 80,
                    "to_port": 80,
                    "cidr_blocks": ["0.0.0.0/0"],
                }
            ]
        if args.ssh_access:
            ingress.append(
                {
                    "protocol": "tcp",
                    "from_port": 22,
                    "to_port": 22,
                    "cidr_blocks": ["0.0.0.0/0"],
                }
            )

        self.tm_sg = aws.ec2.SecurityGroup(
            "testerSg",
            description="Allow tester access",
            vpc_id=self.vpc.id,
            ingress=ingress,
            egress=[
                {
                    "protocol": "tcp",
                    "from_port": 80,
                    "to_port": 80,
                    "cidr_blocks": ["0.0.0.0/0"],
                },
                {
                    "protocol": "tcp",
                    "from_port": 443,
                    "to_port": 443,
                    "cidr_blocks": ["0.0.0.0/0"],
                }
            ],
            tags={"Name": args.prefix},
            opts=pulumi.ResourceOptions(parent=self),
        )
