# terraform-aws-eks

Opinionated Terraform module for provisioning EKS clusters with managed node groups, core addons, optional EBS CSI, and optional Karpenter. Uses Pod Identity for all workload IAM (no OIDC provider needed).

## Usage

### Basic

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

### With Karpenter

```hcl
module "eks" {
  source = "git::git@github.com:tentozen/terraform-aws-eks.git?ref=main"

  app_name           = "myapp"
  environment        = "prod"
  region             = "us-east-1"
  vpc_id             = module.networking.vpc_id
  private_subnet_ids = module.networking.private_subnet_ids
  public_subnet_ids  = module.networking.public_subnet_ids
  eks_version        = "1.31"

  deploy_karpenter = true
  karpenter_version = "1.1.1"

  # Managed node group still runs core workloads + Karpenter itself
  node_group_instance_types = ["t3.large"]
  desired_size              = 2
  min_size                  = 2
  max_size                  = 3
}
```

Consumer wiring (e.g. dojo with `terraform_remote_state`):

```hcl
data "terraform_remote_state" "eks" {
  backend = "s3"
  config = {
    bucket = "myapp-terraform-state"
    key    = "eks/terraform.tfstate"
    region = "us-east-1"
  }
}

provider "kubernetes" {
  host                   = data.terraform_remote_state.eks.outputs.cluster_endpoint
  cluster_ca_certificate = base64decode(data.terraform_remote_state.eks.outputs.cluster_ca_certificate)

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", data.terraform_remote_state.eks.outputs.cluster_name]
  }
}

# Karpenter EC2NodeClass references the node role output
resource "kubectl_manifest" "ec2nodeclass" {
  yaml_body = yamlencode({
    apiVersion = "karpenter.k8s.aws/v1"
    kind       = "EC2NodeClass"
    metadata   = { name = "default" }
    spec = {
      role = data.terraform_remote_state.eks.outputs.karpenter_node_role_name
      # ...
    }
  })
}
```

## What gets created

| Resource | Always | With `deploy_ebs_csi` | With `deploy_karpenter` |
|---|---|---|---|
| EKS cluster (private endpoint, API auth) | x | | |
| Cluster IAM role | x | | |
| Managed node group | x | | |
| Node group IAM role | x | | |
| Subnet tags (karpenter, elb) | x | | |
| VPC CNI addon | x | | |
| kube-proxy addon | x | | |
| CoreDNS addon | x | | |
| Pod Identity Agent addon | x | | |
| EBS CSI driver addon | | x | |
| EBS CSI Pod Identity role | | x | |
| gp3 StorageClass (default) | | x | |
| Karpenter controller IAM role | | | x |
| Karpenter node IAM role | | | x |
| EKS access entry (EC2_LINUX) | | | x |
| SQS interruption queue | | | x |
| EventBridge rules (4) | | | x |
| Karpenter Helm release | | | x |

## Variables

| Name | Type | Default | Description |
|---|---|---|---|
| `app_name` | `string` | required | Application name, used for resource naming and tagging |
| `environment` | `string` | required | Environment name (e.g. dev, staging, prod) |
| `region` | `string` | required | AWS region |
| `vpc_id` | `string` | required | VPC ID where the EKS cluster will be deployed |
| `private_subnet_ids` | `list(string)` | required | Private subnet IDs for EKS cluster and node groups |
| `public_subnet_ids` | `list(string)` | required | Public subnet IDs for load balancers |
| `eks_version` | `string` | required | Kubernetes version for the EKS cluster |
| `node_group_instance_types` | `list(string)` | `["t3.medium"]` | Instance types for the managed node group |
| `capacity_type` | `string` | `"ON_DEMAND"` | Capacity type (ON_DEMAND or SPOT) |
| `ami_type` | `string` | `"AL2023_x86_64_STANDARD"` | AMI type for the managed node group |
| `desired_size` | `number` | `2` | Desired number of nodes |
| `min_size` | `number` | `1` | Minimum number of nodes |
| `max_size` | `number` | `4` | Maximum number of nodes |
| `deploy_ebs_csi` | `bool` | `true` | Deploy EBS CSI driver with Pod Identity |
| `deploy_karpenter` | `bool` | `false` | Deploy Karpenter with Pod Identity |
| `vpc_cni_version` | `string` | `"v1.19.2-eksbuild.1"` | VPC CNI addon version |
| `kube_proxy_version` | `string` | `"v1.31.4-eksbuild.1"` | kube-proxy addon version |
| `coredns_version` | `string` | `"v1.11.4-eksbuild.2"` | CoreDNS addon version |
| `pod_identity_agent_version` | `string` | `"v1.3.5-eksbuild.2"` | Pod Identity Agent addon version |
| `ebs_csi_version` | `string` | `"v1.38.1-eksbuild.2"` | EBS CSI driver addon version |
| `karpenter_version` | `string` | `"1.1.1"` | Karpenter Helm chart version |

## Outputs

| Name | Description |
|---|---|
| `cluster_name` | Name of the EKS cluster |
| `cluster_endpoint` | Endpoint for the EKS cluster API server |
| `cluster_ca_certificate` | Base64-encoded CA data for the cluster |
| `cluster_security_group_id` | Security group ID attached to the EKS cluster |
| `node_group_role_name` | Name of the IAM role for the managed node group |
| `karpenter_node_role_name` | Name of the Karpenter node IAM role (empty if not deployed) |

## Design decisions

- **Pod Identity over IRSA** — no OIDC provider needed, simpler trust policies, automatic session tags for ABAC. See `research/karpenter-pod-identity.md`.
- **API auth mode** — uses `API` authentication mode (not `CONFIG_MAP`), enabling EKS access entries.
- **Private + public endpoint** — private for in-cluster traffic, public for Terraform and developer access.
- **Managed node group always present** — runs core workloads and Karpenter itself. Karpenter manages additional capacity.
- **Feature flags** — `deploy_ebs_csi` (default true) and `deploy_karpenter` (default false) control optional components. No conditional complexity leaks to consumers.
- **Pinned addon versions** — all addon versions have pinned defaults but are overridable. Consumers upgrade explicitly.
- **SQS interruption queue** — required for Karpenter spot interruption handling. EventBridge routes health events, spot warnings, rebalance recommendations, and state changes.
- **Subnet tagging** — module tags private subnets for Karpenter discovery and internal ELB, public subnets for external ELB.
