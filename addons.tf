# -----------------------------------------------------
# Core Addons (always deployed)
# -----------------------------------------------------

resource "aws_eks_addon" "vpc_cni" {
  cluster_name  = aws_eks_cluster.this.name
  addon_name    = "vpc-cni"
  addon_version = var.vpc_cni_version

  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  depends_on = [aws_eks_node_group.this]
}

resource "aws_eks_addon" "kube_proxy" {
  cluster_name  = aws_eks_cluster.this.name
  addon_name    = "kube-proxy"
  addon_version = var.kube_proxy_version

  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  depends_on = [aws_eks_node_group.this]
}

resource "aws_eks_addon" "coredns" {
  cluster_name  = aws_eks_cluster.this.name
  addon_name    = "coredns"
  addon_version = var.coredns_version

  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  depends_on = [aws_eks_node_group.this]
}

resource "aws_eks_addon" "pod_identity_agent" {
  cluster_name  = aws_eks_cluster.this.name
  addon_name    = "eks-pod-identity-agent"
  addon_version = var.pod_identity_agent_version

  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  depends_on = [aws_eks_node_group.this]
}

# -----------------------------------------------------
# EBS CSI Driver (behind deploy_ebs_csi flag)
# -----------------------------------------------------

resource "aws_iam_role" "ebs_csi" {
  count = var.deploy_ebs_csi ? 1 : 0
  name  = "${local.cluster_name}-ebs-csi"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "pods.eks.amazonaws.com"
      }
      Action = ["sts:AssumeRole", "sts:TagSession"]
    }]
  })

  tags = local.default_tags
}

resource "aws_iam_role_policy_attachment" "ebs_csi" {
  count      = var.deploy_ebs_csi ? 1 : 0
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
  role       = aws_iam_role.ebs_csi[0].name
}

resource "aws_eks_pod_identity_association" "ebs_csi" {
  count = var.deploy_ebs_csi ? 1 : 0

  cluster_name    = aws_eks_cluster.this.name
  namespace       = "kube-system"
  service_account = "ebs-csi-controller-sa"
  role_arn        = aws_iam_role.ebs_csi[0].arn

  depends_on = [aws_eks_addon.pod_identity_agent]
}

resource "aws_eks_addon" "ebs_csi" {
  count = var.deploy_ebs_csi ? 1 : 0

  cluster_name  = aws_eks_cluster.this.name
  addon_name    = "aws-ebs-csi-driver"
  addon_version = var.ebs_csi_version

  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  depends_on = [
    aws_eks_node_group.this,
    aws_eks_pod_identity_association.ebs_csi,
  ]
}

# -----------------------------------------------------
# gp3 StorageClass (default)
# -----------------------------------------------------

resource "kubernetes_storage_class_v1" "gp3" {
  count = var.deploy_ebs_csi ? 1 : 0

  metadata {
    name = "gp3"
    annotations = {
      "storageclass.kubernetes.io/is-default-class" = "true"
    }
  }

  storage_provisioner = "ebs.csi.aws.com"
  reclaim_policy      = "Delete"
  volume_binding_mode = "WaitForFirstConsumer"

  parameters = {
    type      = "gp3"
    encrypted = "true"
  }

  depends_on = [aws_eks_addon.ebs_csi]
}
