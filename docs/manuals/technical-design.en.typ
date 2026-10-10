#import "lib/template.typ": manual, callout, palette, shot
#import "lib/facts.typ" as facts

#let note = callout.with("note", lang: "en")

#show: manual.with(
  title: "Technical Design Document",
  subtitle: "How the platform is built and why",
  doc-id: "OBE-TDD-001",
  version: "2.0",
  date: facts.doc-date,
  status: "Approved for the dev environment",
  owner: "khaipd18 (DevOps / Cloud)",
  audience: "Cloud and DevOps engineers, reviewers",
  classification: "Internal",
  repository: facts.repo-url,
  lang: "en",
  revisions: (
    ("1.0", "2026-10-09", "First issue.", "khaipd18"),
    ("1.1", "2026-10-10", "First run on the new account; managed log group.", "khaipd18"),
    ("1.2", "2026-10-10", "Full EKS deployment, screenshots, access entries, three nodes, decision D11.", "khaipd18"),
    ("2.0", facts.doc-date, "Rewritten to be shorter: one page per area, repeated content removed.", "khaipd18"),
  ),
  related: (
    [OBE-RUN-001 Operations Runbook: how to run and fix the platform],
    [`docs/infrastructure/`: editable HLD/LLD diagrams and their YAML specs],
  ),
)

= Overview

*What it is.* Google's Online Boutique (10 microservices in 5 languages, gRPC between them) running on Amazon EKS, with everything around it built in this repository: infrastructure as code, CI/CD, GitOps and security controls. The application code in `src/` is upstream code and is not changed.

*Goals.*
- No long-lived AWS keys anywhere; only reviewed code can change AWS.
- Misconfigurations and vulnerable images are caught before they are deployed.
- The cluster can be rebuilt from Git alone; moving to another AWS account needs no code change.
- A dev environment that is cheap to start and to stop.

*Status.* Deployed and tested end to end on EKS on 2026-10-10 (section 7), then destroyed to save cost. One environment (`dev`) in #raw(facts.region).

#figure(image(facts.fig.hld, width: 100%), caption: [High-level architecture])

Users reach the shop through a load balancer in the public subnets; the worker nodes sit in private subnets. Nodes reach ECR, STS and S3 through VPC endpoints and the internet through one NAT Gateway. Argo CD inside the cluster pulls the desired state from GitHub.

= AWS infrastructure

== Network

#table(
  columns: (auto, auto, auto, 1fr),
  [Subnet], [AZ ID], [CIDR], [Contains],
  ..facts.subnets.flatten(),
)

- VPC #raw(facts.vpc-cidr) in two AZs, placed by AZ ID because AZ names differ between accounts.
- One NAT Gateway for both AZs to save cost (decision D3).
- VPC endpoints for `ecr.api`, `ecr.dkr`, `sts` and S3, so image pulls stay inside the VPC #link(facts.src.ecr-endpoints)[[AWS]].
- Traffic is filtered by security groups and Kubernetes NetworkPolicy; the network ACLs allow everything.

#figure(image(facts.fig.network, width: 100%), caption: [LLD: network detail])

== EKS, ECR and state

#table(
  columns: (22%, 1fr),
  [Part], [Design],
  [EKS cluster], [#raw(facts.cluster), Kubernetes 1.35 (standard support until 27 March 2027 #link(facts.src.versions)[[AWS]]); public and private API endpoint; all control plane logs to CloudWatch (365 days)],
  [Nodes], [Managed node group, 3 × `t3.medium` (min 1, max 4), Amazon Linux 2023, private subnets only],
  [Add-ons], [VPC CNI with NetworkPolicy enforcement, CoreDNS, kube-proxy, Metrics Server],
  [Cluster access], [EKS access entries: the creator is admin, the console role is read-only (`AmazonEKSAdminViewPolicy`) #link(facts.src.access-entries)[[AWS]]],
  [ECR], [10 repositories, immutable tags (tag = git SHA), scan on push, old images cleaned up by a lifecycle policy #link(facts.src.ecr-immutable)[[AWS]]],
  [Terraform state], [S3 bucket #raw(facts.state-bucket) (versioned, encrypted) and DynamoDB lock table; created once by hand],
)

Terraform is split into five modules: `vpc`, `eks`, `ecr`, `vpc-endpoints` and `github-oidc-role`. The account ID is never written in the code.

== Access for CI (GitHub OIDC)

GitHub Actions gets short-lived AWS credentials from the GitHub OIDC provider. Each role trusts one exact `sub` value of the token #link(facts.src.oidc-role)[[AWS]]:

#table(
  columns: (auto, auto, 1fr),
  [Role], [Trusted `sub`], [Used for],
  [`github-actions-ecr-oidc-role`], [`ref:refs/heads/main`], [CI pushes images],
  [`github-actions-terraform-plan-oidc-role`], [`pull_request`], [Read-only `terraform plan` on PRs],
  [`github-actions-terraform-oidc-role`], [`environment:production`], [`terraform apply`, only after a reviewer approves],
)

#figure(image(facts.fig.cicd, width: 100%), caption: [LLD: CI/CD and IAM OIDC])

= Kubernetes platform

All services run in namespace #raw(facts.namespace). Every release uses the same Helm chart (`helm-charts/`); each service's values file only says what is different.

#table(
  columns: (auto, auto, auto, 1fr, auto, auto),
  [Service], [Language], [Port], [Accepts calls from], [CPU req/limit], [Memory req/limit],
  ..facts.services.flatten(),
)

*Secure by default.* Pods run as non-root with a read-only file system, no Linux capabilities and no service account token. Pod Security Admission (`restricted`) rejects any pod that does not follow these rules.

*Who may call whom.* Each service has a NetworkPolicy that only lets in the callers listed in its values file (`allowFrom`).

#figure(image(facts.fig.traffic, width: 100%), caption: [Calls allowed between services])

*Resilience.* `frontend` runs 2–4 replicas with a CPU autoscaler (HPA), a PodDisruptionBudget and spreading across zones. The other services run one replica. `redis-cart` keeps carts in memory, so they are lost when it restarts.

*Monitoring.* Prometheus and Grafana (`kube-prometheus-stack`) in namespace `monitoring`; control plane logs in CloudWatch. No custom alerts yet.

= Delivery pipeline

#figure(image(facts.fig.pipeline, width: 100%), caption: [From commit to cluster])

*CI (one workflow per language).* For each changed service: lint, test and dependency scan → build the image → Trivy scan (results in the GitHub Security tab, SBOM saved) → push to ECR with the git SHA as tag → write the tag into `gitops/dev-eks/`. Without the `AWS_ACCOUNT_ID` variable, CI still lints, tests, builds and scans, and skips the AWS steps.

#table(
  columns: (auto, 1fr, 1fr, 1fr),
  [Stack], [Lint / format], [Test], [Dependency scan],
  ..facts.gates.flatten(),
)

Checks marked *warning* need changes in the upstream code, so they are shown but do not fail the run.

*CD.* One Argo CD ApplicationSet creates 12 Applications from `gitops/dev-eks/` and keeps them in sync: changes in Git are applied, changes made by hand are undone.

*Infrastructure.* A pull request that changes `terraform/` runs Checkov (blocking) and a read-only `terraform plan`. After the merge, `terraform apply` waits for a reviewer in the GitHub environment `production`. The `main` branch is protected by the ruleset `protect-main`.

= Security

#table(
  columns: (28%, 1fr),
  [Risk], [Control],
  [Leaked access keys], [No keys: GitHub OIDC for CI, IRSA for the VPC CNI],
  [Unreviewed change reaches AWS], [PRs get a read-only role; apply needs `main` and an approval],
  [Misconfigured Terraform], [Checkov blocks before plan and apply],
  [Vulnerable images], [Trivy before push; findings in code scanning; SBOM per image],
  [Image overwritten], [Immutable ECR tags],
  [Compromised container], [Non-root, read-only file system, no capabilities, PSA `restricted`],
  [Moving between services], [NetworkPolicy per service],
)

*Accepted findings.* 13 Checkov findings are reviewed and kept in `terraform/.checkov.baseline`:

#table(
  columns: (auto, 1fr),
  [Check], [Why it is accepted],
  [`CKV_AWS_39` public EKS endpoint], [Needed without a VPN; restrict later (roadmap)],
  [`CKV_AWS_58`, `CKV_AWS_158` no customer KMS key], [EKS and CloudWatch Logs already encrypt the data with AWS keys #link(facts.src.envelope)[[AWS]]],
  [`CKV_AWS_229`–`232` open NACL ports], [Filtering is done by security groups and NetworkPolicy],
  [`CKV2_AWS_11` no VPC flow logs], [Cost; enable for production],
  [`CKV2_AWS_12` default security group], [Not used by any resource],
)

= Design decisions

#table(
  columns: (5%, 30%, 1fr),
  [ID], [Decision], [Why / when to revisit],
  [D1], [GitHub OIDC instead of access keys], [Nothing to leak or rotate.],
  [D2], [Apply needs approval in a GitHub environment], [A merge alone cannot change infrastructure.],
  [D3], [One NAT Gateway for two AZs], [Cheaper for dev. For production use a regional NAT gateway #link(facts.src.regional-nat)[[AWS]].],
  [D4], [One Helm chart for all services], [Security defaults written once; a new service is one values file.],
  [D5], [ApplicationSet with a fixed list], [What is deployed is visible in Git. Revisit with more environments.],
  [D6], [Image tag = git SHA, immutable], [Every running image maps to a commit; rollback = previous SHA.],
  [D7], [Classic Load Balancer from a Service], [No extra controller for dev. Revisit when TLS or WAF is needed.],
  [D8], [IRSA for the VPC CNI], [Works everywhere. EKS Pod Identity is now simpler #link(facts.src.pod-identity)[[AWS]].],
  [D9], [DynamoDB state locking], [Works with every Terraform version; move to S3 locking later.],
  [D10], [Upstream findings as warnings], [The app code is not maintained here.],
  [D11], [Argo CD installed in the cluster], [Free and fully controlled. EKS can also run Argo CD as a managed capability #link(facts.src.capabilities)[[AWS]].],
  [D12], [Three nodes by default], [The full stack needs about 37 pods; two `t3.medium` nodes are not enough #link(facts.src.max-pods)[[AWS]].],
)

= Verification <verification>

#table(
  columns: (28%, 1fr),
  [Test], [Result],
  [Full deployment on EKS (2026-10-10)], [74 resources on 3 nodes; Argo CD synced all 14 apps; a test order went through; PSA rejected a bad pod and NetworkPolicy blocked 2/2 disallowed connections; destroyed afterwards],
  [kind cluster (local)], [All pods ready; checkout works; HPA scaled 2 → 3 under load; PDB blocked draining the last `frontend` node],
  [Terraform], [`fmt`, `validate`, Checkov pass; plan = 74 resources],
  [CI without AWS], [All 5 language pipelines green; Trivy results for all 10 images],
  [First EKS run (May 2026)], [Images pushed over OIDC and synced by Argo CD (bot commits `14bc93f`, `eb86a9a`, `46e66d5`)],
)

#shot("terminal-security.png", [Security controls checked on EKS: PSA rejects a non-compliant pod; NetworkPolicy blocks disallowed calls])

= Risks and roadmap <risks>

*Known risks:* the `main` ruleset blocks the CI bot's GitOps commit (switched off during bootstrap); one NAT Gateway is a single point of failure; ten services have one replica; carts are lost when `redis-cart` restarts; several images have known vulnerabilities; the EKS API endpoint is open to the internet (IAM still required).

*Roadmap*, in order:
+ Let the CI bot update `gitops/` under the ruleset (deploy key or pull requests).
+ Upgrade service dependencies, then make the vulnerability gates blocking.
+ Restrict the EKS public endpoint; narrow `ecr-endpoint-sg` to `tcp/443`.
+ Regional NAT gateway; AWS Load Balancer Controller with TLS.
+ External Secrets with AWS Secrets Manager; signed images pinned by digest.
+ Staging and production environments; SLO-based alerts.
+ S3 state locking; consider EKS Pod Identity and the Argo CD capability.

#heading(numbering: none)[Appendix. Versions]

#table(
  columns: (32%, 28%, 1fr),
  [Component], [Version], [Defined in],
  ..facts.versions.flatten(),
)
