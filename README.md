# terraform-aws-eks

Opinionated Terraform module for provisioning EKS clusters with managed node groups, core addons, optional EBS CSI, and optional Karpenter.

## Usage

```hcl
module "eks" {
  source = "git::git@github.com:tentozen/terraform-aws-eks.git?ref=main"

  app_name           = "myapp"
  environment        = "dev"
  region             = "us-east-1"
  vpc_id             = module.networking.vpc_id
  private_subnet_ids = module.networking.private_subnet_ids
  public_subnet_ids  = module.networking.public_subnet_ids
  eks_version        = "1.31"
}
```
