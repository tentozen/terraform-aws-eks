# Karpenter + Pod Identity Research

Research for [#5](https://github.com/tentozen/terraform-aws-eks/issues/5).

## 1. Does Karpenter v1.x support Pod Identity natively?

**Yes.** Pod Identity support was added in Karpenter v0.34.0 (Feb 2024). By v1.0.0 it is the recommended method. The controller uses the standard AWS SDK credential chain — Pod Identity works via the EKS Pod Identity Agent DaemonSet addon (`eks-pod-identity-agent`), which is already in our core addons list.

## 2. IAM policy differences: Pod Identity vs OIDC

The **permissions policy is identical** between IRSA and Pod Identity. Only the **trust policy** differs:

**IRSA (OIDC):**
```json
{
  "Effect": "Allow",
  "Principal": {
    "Federated": "arn:aws:iam::oidc-provider/oidc.eks.<region>.amazonaws.com/id/<OIDC_ID>"
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

Key difference: Pod Identity requires `sts:TagSession` in addition to `sts:AssumeRole`.

## 3. Is the SQS spot interruption queue still needed?

**Yes, still recommended.** SQS provides proactive 2-minute spot interruption warnings via EventBridge. Without it, Karpenter can only reactively detect terminated instances via `DescribeInstances` polling. There is no native replacement that eliminates the need for SQS.

EventBridge rules needed:
- Spot interruption warnings → SQS
- EC2 instance state change notifications → SQS
- EC2 instance rebalance recommendations → SQS
- AWS health events → SQS

## 4. Latest stable chart version

As of research time: **v1.1.1** from `oci://public.ecr.aws/karpenter/karpenter`. Verify at implementation time.

## 5. Migration gotchas (OIDC → Pod Identity)

1. **Pod Identity Agent addon must be installed first** — the `eks-pod-identity-agent` DaemonSet must be running before creating the Pod Identity association
2. **Remove the SA annotation** — delete the `eks.amazonaws.com/role-arn` annotation from the Karpenter ServiceAccount; Pod Identity doesn't use it
3. **`sts:TagSession` required** — the trust policy must include this action or assumption fails silently
4. **Namespace must match** — the `aws_eks_pod_identity_association` must reference the exact namespace (`kube-system`) and service account name (`karpenter`)
5. **Brief restart window** — Karpenter pods must restart to pick up Pod Identity credentials; plan for a brief interruption in scaling decisions
6. **No OIDC provider needed** — the module does not need to create or reference an OIDC provider, simplifying the dependency graph
7. **Credential refresh** — Pod Identity handles credential rotation automatically; no expiry concerns
8. **Terraform ordering** — the `aws_eks_pod_identity_association` must depend on both the IAM role and the EKS addon being ready
9. **Helm chart values** — ensure `settings.clusterName` and `settings.interruptionQueue` are set; no IRSA-specific annotations in the Helm values

## Implementation summary

| Concern | Approach |
|---|---|
| Controller IAM | Pod Identity role + association, no OIDC provider |
| Trust policy | `pods.eks.amazonaws.com` with `sts:AssumeRole` + `sts:TagSession` |
| Node role | Separate EC2 role (EKSWorkerNodePolicy, CNI, ECR, SSM) |
| SQS | Yes, keep the interruption queue + EventBridge rules |
| Chart source | `oci://public.ecr.aws/karpenter/karpenter` v1.1.1 |
| Access entry | Register Karpenter node role as `EC2_LINUX` |
