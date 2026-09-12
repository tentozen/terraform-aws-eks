# Karpenter + Pod Identity Research

Research for [#5](https://github.com/tentozen/terraform-aws-eks/issues/5).

## 1. Does Karpenter v1.x support Pod Identity natively?

**Yes.** Pod Identity is the recommended method in Karpenter v1.x. The v1.0 migration replaced the `karpenter.sh/managed-by` label with `eks:eks-cluster-name` specifically to enable Pod Identity ABAC policies. The controller uses the standard AWS SDK credential chain — Pod Identity works via the EKS Pod Identity Agent DaemonSet addon (`eks-pod-identity-agent`), which is already in our core addons list.

The official getting-started guide uses `podIdentityAssociations` in the CloudFormation template, confirming it as the primary path.

Sources: [Karpenter Getting Started](https://karpenter.sh/docs/getting-started/getting-started-with-karpenter/), [v1 Migration](https://karpenter.sh/v1.0/upgrading/v1-migration/)

## 2. IAM policy differences: Pod Identity vs OIDC

The **permissions policies are identical** between IRSA and Pod Identity. Karpenter needs six policies:

1. **KarpenterControllerNodeLifecyclePolicy** — node provisioning and termination
2. **KarpenterControllerIAMIntegrationPolicy** — IAM role operations
3. **KarpenterControllerEKSIntegrationPolicy** — EKS cluster integration
4. **KarpenterControllerInterruptionPolicy** — EC2 interruption handling via SQS
5. **KarpenterControllerResourceDiscoveryPolicy** — subnet/SG discovery
6. **KarpenterControllerZonalShiftPolicy** — AWS ARC Zonal Shift

Only the **trust policy** differs:

**IRSA (OIDC):**
```json
{
  "Effect": "Allow",
  "Principal": {
    "Federated": "arn:aws:iam::<account>:oidc-provider/oidc.eks.<region>.amazonaws.com/id/<OIDC_ID>"
  },
  "Action": "sts:AssumeRoleWithWebIdentity",
  "Condition": {
    "StringEquals": {
      "<oidc>:sub": "system:serviceaccount:kube-system:karpenter",
      "<oidc>:aud": "sts.amazonaws.com"
    }
  }
}
```

**Pod Identity:**
```json
{
  "Effect": "Allow",
  "Principal": {
    "Service": "pods.eks.amazonaws.com"
  },
  "Action": ["sts:AssumeRole", "sts:TagSession"]
}
```

Key difference: Pod Identity requires `sts:TagSession` in addition to `sts:AssumeRole`. Pod Identity also injects automatic session tags (`eks-cluster-name`, `kubernetes-namespace`, `kubernetes-service-account`, `kubernetes-pod-name`) usable for ABAC policies in CloudTrail.

Sources: [Karpenter Getting Started](https://karpenter.sh/docs/getting-started/getting-started-with-karpenter/), [Pod Identity vs IRSA](https://medium.com/cwan-engineering/eks-pod-identity-the-next-step-beyond-oidc-and-irsa-728f0a13f756)

## 3. Is the SQS spot interruption queue still needed?

**Yes, required for production.** Karpenter watches an SQS queue for interruption events. Without it, Karpenter can only detect instance health via `DescribeInstanceStatus` polling — which does **not** cover Spot interruption warnings (the most time-sensitive events, giving a 2-minute window).

Events handled via SQS:
- Spot Interruption Warnings
- Scheduled Change Health Events (maintenance)
- Instance Terminating Events
- Instance Stopping Events
- Instance Status Check Failures

Configure with: `--set "settings.interruptionQueue=${CLUSTER_NAME}"`

Note: Spot Rebalance Recommendations are published as events but Karpenter does not currently automate responses to them.

Sources: [Karpenter Disruption](https://karpenter.sh/docs/concepts/disruption/), [Interruption Handling Design](https://github.com/aws/karpenter/blob/main/designs/interruption-handling.md)

## 4. Latest stable chart version

**v1.14.1 (LTS)** — released August 2024, supported through July 2027. This is the latest release from `oci://public.ecr.aws/karpenter/karpenter`.

Compatibility: Karpenter v1.13+ requires Kubernetes 1.36+. For our likely EKS versions:
- K8s 1.31 → Karpenter >= 1.0.5
- K8s 1.32 → Karpenter >= 1.2
- K8s 1.33 → Karpenter >= 1.5

**Recommendation:** Pin to a version compatible with the `eks_version` variable. Default to a version that supports K8s 1.31+ (e.g. `1.0.5` or latest in the 1.x line compatible with target K8s).

Sources: [Karpenter Releases](https://github.com/aws/karpenter-provider-aws/releases), [Compatibility Matrix](https://karpenter.sh/docs/upgrading/compatibility/)

## 5. Migration gotchas (OIDC → Pod Identity)

1. **Pod Identity Agent addon must be installed first** — the `eks-pod-identity-agent` DaemonSet must be running before creating the Pod Identity association
2. **Remove the SA annotation** — delete the `eks.amazonaws.com/role-arn` annotation from the Karpenter ServiceAccount; otherwise pods still attempt IRSA and fail
3. **`sts:TagSession` required** — the trust policy must include this action or assumption fails silently
4. **Namespace must match** — the `aws_eks_pod_identity_association` must reference the exact namespace (`kube-system`) and service account name (`karpenter`)
5. **Fargate not supported** — Pod Identity does not work on Fargate; Karpenter must run on managed nodes or self-managed nodes
6. **hostNetwork consideration** — Karpenter runs with `hostNetwork: true`; traffic uses the Pod Identity Agent rather than OIDC, requiring different IAM config
7. **No OIDC provider needed** — the module does not need to create or reference an OIDC provider, simplifying the dependency graph
8. **Terraform ordering** — the `aws_eks_pod_identity_association` must depend on both the IAM role and the EKS addon being ready
9. **Helm chart values** — ensure `settings.clusterName` and `settings.interruptionQueue` are set; no IRSA-specific annotations in the Helm values

Sources: [IRSA to Pod Identity Migration](https://blog.devops.dev/we-ditched-irsa-for-pod-identity-when-setting-up-karpenter-heres-exactly-how-we-did-it-7c250d83ad06), [Pod Identity for Karpenter on host network](https://repost.aws/questions/QU2zjzTa8bTdm3_-uSOo5Onw/eks-pod-identity-for-karpenter-running-on-host-network), [terraform-aws-eks IRSA issue](https://github.com/terraform-aws-modules/terraform-aws-eks/issues/3544)

## Implementation summary

| Concern | Approach |
|---|---|
| Controller IAM | Pod Identity role + association, no OIDC provider |
| Trust policy | `pods.eks.amazonaws.com` with `sts:AssumeRole` + `sts:TagSession` |
| Permissions | 6 managed-style policies (node lifecycle, IAM, EKS, interruption, resource discovery, zonal shift) |
| Node role | Separate EC2 role (EKSWorkerNodePolicy, CNI, ECR, SSM) |
| SQS | Yes, keep the interruption queue + EventBridge rules (5 event types) |
| Chart source | `oci://public.ecr.aws/karpenter/karpenter` — pin version compatible with target K8s |
| Access entry | Register Karpenter node role as `EC2_LINUX` |
| Helm settings | `settings.clusterName`, `settings.interruptionQueue` |
