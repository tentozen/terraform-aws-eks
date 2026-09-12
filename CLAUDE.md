## Project

Reusable Terraform module for provisioning opinionated EKS clusters with managed node groups, core addons, optional EBS CSI, and optional Karpenter.

## Prior art

- `glowing-potato` 02-compute (commit `48bad76`) — original EKS setup
- `client-grit` modules (eks_control_plane, eks_node_group, pod_identity)
- `terraform-aws-networking` — pattern reference for opinionated, feature-flagged modules
- `runbooks/rca/2026-06-02-egress-proxy-route-ownership.md` — module boundary lessons

## Conventions

- Follow `terraform-aws-networking` module pattern: opinionated, feature-flagged, loose coupling via variables
- Standard Terraform file layout: `main.tf`, `variables.tf`, `outputs.tf`, `versions.tf`
- Optional features gated by `deploy_*` boolean variables (e.g. `deploy_ebs_csi`, `deploy_karpenter`)

## Agent skills

### Issue tracker

GitHub Issues on this repo. See `docs/agents/issue-tracker.md`.

### Domain docs

Single-context layout (`CONTEXT.md` + `docs/adr/`). See `docs/agents/domain.md`.
