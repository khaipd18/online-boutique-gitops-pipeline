# Online Boutique on EKS: a real DevSecOps pipeline, from commit to production

**English** | [Tiếng Việt](README.vi.md)

> Push one line of code and everything else runs on its own: lint, test, scan, build the image, push it to ECR, update Git, and let Argo CD sync it to EKS. Not a single access key lives in this repo.

![Terraform](https://img.shields.io/badge/IaC-Terraform_1.14-7B42BC?logo=terraform&logoColor=white)
![Amazon EKS](https://img.shields.io/badge/Amazon_EKS-1.35-FF9900?logo=amazoneks&logoColor=white)
![Argo CD](https://img.shields.io/badge/GitOps-Argo_CD-EF7B4D?logo=argo&logoColor=white)
![Helm](https://img.shields.io/badge/Helm-universal_chart-0F1689?logo=helm&logoColor=white)
![GitHub Actions](https://img.shields.io/badge/CI-GitHub_Actions-2088FF?logo=githubactions&logoColor=white)
![Checkov](https://img.shields.io/badge/IaC_scan-Checkov-6C47FF)
![Trivy](https://img.shields.io/badge/Image_scan-Trivy-1904DA?logo=aquasecurity&logoColor=white)

---

## About

This is a personal DevOps/DevSecOps project. I took Google's [Online Boutique](https://github.com/GoogleCloudPlatform/microservices-demo), an e-commerce system of 10 microservices written in 5 languages (Go, C#, Java, Node.js, Python) that talk to each other over gRPC, and built everything around it to run it on AWS properly: infrastructure, CI/CD, GitOps and the security layers.

One question drove the whole project: *"If this were a real production system, how would I build and protect it?"* So the repo does not stop at "it deploys". It goes on to the things an operations team actually cares about: least privilege for the pipeline, no long-lived credentials, misconfigurations blocked before `apply`, images scanned before they are pushed, and network isolation between services.

| | |
|---|---|
| **Role** | Designed and built all of the infrastructure, pipelines and deployment configuration |
| **Application** | Online Boutique (the original source code in `src/` is kept unchanged) |
| **Cloud** | AWS, region `ap-southeast-1` |
| **Focus** | Infrastructure as Code, GitOps, DevSecOps, least privilege |

---

## Highlights

- 🏗️ **72 AWS resources** built entirely with Terraform modules: a 2-AZ VPC, EKS, ECR, VPC endpoints, IAM OIDC.
- 🔑 **Zero long-lived credentials.** GitHub Actions reaches AWS through OIDC and pods use IRSA. Trust policies are pinned down to the `sub` claim: only `main` may `apply` or push images, while pull requests may only `plan` with a read-only role.
- 🧪 **5 CI pipelines for 5 languages**, building only the services that changed thanks to path filters and a dynamic matrix.
- 🛡️ **Security gates before anything reaches AWS:** Checkov blocks misconfigured Terraform before `plan`/`apply`, and Trivy scans every image before it is pushed, publishing results to GitHub's *Security* tab along with a CycloneDX SBOM.
- 🔁 **A closed GitOps loop:** CI writes the image's git SHA into `gitops/`, and an Argo CD ApplicationSet syncs it to the cluster and reverts any manual change (self-heal).
- 🔒 **Pod hardening and network segmentation:** non-root, read-only root filesystem, all capabilities dropped, Pod Security Admission `restricted`, and NetworkPolicies that open only the gRPC paths that are actually needed.
- ✅ **Evidence, not just code:** end-to-end checkout works, NetworkPolicy blocks 3/3 unauthorized connections, and Checkov findings on the Kubernetes manifests dropped from **128 to 12** ([details](#verification-results)).

---

## Architecture

### Infrastructure on AWS

![AWS high-level architecture](docs/infrastructure/images/aws-hld.png)

Inbound traffic enters through the Internet Gateway to the load balancer in the public subnets, which forwards it to the EKS worker nodes in the private subnets ([inbound traffic path](https://docs.aws.amazon.com/prescriptive-guidance/latest/load-balancer-stickiness/subnets-routing.html)). Worker nodes live entirely in private subnets. Traffic to ECR, STS and S3 (where ECR stores image layers) goes through VPC endpoints, so it neither detours through the NAT Gateway nor leaves for the internet ([ECR VPC endpoints](https://docs.aws.amazon.com/AmazonECR/latest/userguide/vpc-endpoints.html)). Subnets are pinned by AZ ID (`apse1-az1`, `apse1-az2`) because AZ names map differently in every account. A single NAT Gateway shared by both AZs is a deliberate cost trade-off for a dev environment.

<details>
<summary><b>Low-level design: network, security groups, CI/CD and IAM OIDC</b></summary>
<br>

**Network detail**: CIDR of every subnet, route tables, VPC endpoints, NACLs.

![AWS LLD network](docs/infrastructure/images/aws-lld-network.png)

**Security group flow**: traffic flows with their ports, and the inbound rules of every security group.

![AWS LLD security groups](docs/infrastructure/images/aws-lld-security-groups.png)

**CI/CD and IAM OIDC**: which role can be assumed from where, with which permissions, against which resources.

![AWS LLD CI/CD and IAM](docs/infrastructure/images/aws-lld-cicd-iam.png)

Editable draw.io sources: [`aws-hld.drawio`](docs/infrastructure/aws-hld.drawio), [`aws-lld.drawio`](docs/infrastructure/aws-lld.drawio). The diagrams are generated from YAML specs ([`aws-hld.spec.yaml`](docs/infrastructure/aws-hld.spec.yaml), [`aws-lld.spec.yaml`](docs/infrastructure/aws-lld.spec.yaml)) whose values come straight from `terraform/`.
</details>

### From commit to cluster

![Delivery pipeline](docs/infrastructure/images/aws-delivery-pipeline.png)

### Who may call whom (NetworkPolicy)

Each service only accepts traffic from the services that need to call it, following the arrows below. Every other connection is denied.

![In-cluster traffic and NetworkPolicy](docs/infrastructure/images/aws-in-cluster-traffic.png)

---

## Tech stack

| Layer | Tools | Version |
|---|---|---|
| Infrastructure as Code | Terraform, AWS provider | 1.14.8, 6.39.0 |
| Kubernetes | Amazon EKS, managed node group AL2023 | 1.35 |
| EKS add-ons | VPC CNI (network policy enabled), CoreDNS, kube-proxy | v1.21.1, v1.13.2, v1.35.3 |
| Container registry | Amazon ECR, immutable tags, registry-level scan on push | – |
| CI | GitHub Actions, `dorny/paths-filter`, composite action | – |
| Security scanning | Checkov (IaC), Trivy (image, SARIF, CycloneDX SBOM) | 3.3.22, 0.75.0 |
| Packaging | Helm (universal chart), Kustomize | – |
| CD | Argo CD ApplicationSet | stable |
| Observability | kube-prometheus-stack (Prometheus, Grafana) | 84.4.0 |

---

## How it works

### Infrastructure as Code

The infrastructure is split into small modules that each do one job. The account ID is not hardcoded anywhere: Terraform reads it from the active credentials and the workflows read it from the `AWS_ACCOUNT_ID` repository variable. Moving to another account needs no code change.

<details>
<summary><b>Terraform modules in detail</b></summary>
<br>

| Module | What it creates |
|---|---|
| `vpc` | VPC, 2 public + 2 private subnets across 2 AZs, Internet Gateway, NAT Gateway, route tables, NACLs |
| `eks` | EKS cluster (all 5 control plane log types enabled), managed node group, VPC CNI/CoreDNS/kube-proxy add-ons, OIDC provider for IRSA |
| `ecr` | 10 repositories with `IMMUTABLE` tags; a lifecycle policy that expires untagged images after 14 days and archives images nobody pulled for 90 days; scan on push configured at registry level, as AWS recommends |
| `vpc-endpoints` | Interface endpoints `ecr.api`, `ecr.dkr`, `sts` and a gateway endpoint for S3 |
| `github-oidc-role` | IAM roles for GitHub Actions, with trust policies pinned to the `sub` claim |

- **Remote state:** encrypted S3, state locking with DynamoDB.
- **IRSA:** the VPC CNI runs with its own IAM role bound to the `kube-system/aws-node` service account instead of borrowing the node's permissions ([IRSA](https://docs.aws.amazon.com/eks/latest/best-practices/identity-and-access-management.html)).
- **Network policy:** the VPC CNI add-on sets `enableNetworkPolicy` so Kubernetes NetworkPolicies are actually enforced on EKS ([EKS docs](https://docs.aws.amazon.com/eks/latest/userguide/cni-network-policy-configure.html)).
</details>

### Continuous Integration

Each language has its own pipeline. On every push, `dorny/paths-filter` works out which services changed, builds a dynamic matrix, and only those services are built. Images are scanned **before** they are pushed, so a problematic image never reaches the registry unnoticed.

<details>
<summary><b>Quality gates per stack</b></summary>
<br>

| Stack | Lint / format | Test | Dependency scan |
|---|---|---|---|
| Go (4 services) | `golangci-lint` (blocking) | `go test` (blocking) | `govulncheck` (warning) |
| .NET (cartservice) | `dotnet format` (warning) | `dotnet test` (blocking) | `dotnet list package --vulnerable` (blocking) |
| Java (adservice) | `google-java-format` (warning) | `gradle test` (blocking) | – |
| Node.js (2 services) | ESLint (blocking) | – | `npm audit` (warning) |
| Python (2 services) | `flake8` (blocking) | `pytest` (blocking when tests exist) | `bandit` (blocking) |

Steps at *warning* level are the ones that can only be fixed by changing Google's original source code. They still show up clearly on every run (annotation and step status) instead of being hidden behind `|| true`.

**Build → scan → push:** the composite action `.github/actions/trivy-scan` scans the image, publishes HIGH/CRITICAL vulnerabilities to GitHub code scanning (SARIF) and stores a CycloneDX SBOM as an artifact. Because ECR tags are immutable, CI skips the build when the image for that commit already exists.

**GitOps write-back:** after pushing the image, CI uses `yq` to write `image.repository` and `image.tag` (the git SHA) into `gitops/dev-eks/values-<service>.yaml`, and a bot commits and pushes it back. A retry loop handles the race when several services build at the same time.
</details>

### Continuous Delivery with Argo CD

One **ApplicationSet** generates an Application per service. They all share **one universal Helm chart** and differ only in their values file. Adding a service means adding one values file and one line to the list generator.

<details>
<summary><b>GitOps configuration in detail</b></summary>
<br>

- `automated`, `prune` and `selfHeal` are on: anyone who edits the cluster by hand gets reverted by Argo CD to what Git says.
- The chart is secure by default (see Security); each service only declares what is different, such as ports, env, resources and probes.
- `frontend-external` is a release containing only a LoadBalancer Service (`deployment.enabled: false`) that targets the `frontend-dev` pods, keeping internet exposure separate from the workload.
- The `dev-eks` namespace is managed by its own Application, labelled for Pod Security Admission and annotated so a sync can never delete it.
- kube-prometheus-stack is deployed by Argo CD with `ServerSideApply=true`, because its CRDs exceed the annotation size limit of client-side apply.
</details>

### Security

Security is layered, each layer addressing a specific risk:

| Risk | Mitigation | Where in the repo |
|---|---|---|
| Leaked access keys | GitHub Actions uses OIDC, pods use IRSA | `terraform/main.tf`, `modules/eks/iam.tf` |
| Any branch or PR gaining AWS admin | The `apply` role and the ECR push role can only be assumed from `ref:refs/heads/main`; PRs only get the read-only `plan` role. Both GitHub's classic `sub` format and its newer immutable format (with owner/repo IDs) are trusted | `modules/github-oidc-role` |
| Misconfigured Terraform | Checkov blocks before `plan`/`apply`. Reviewed findings live in a baseline, and every skipped check carries a written reason | `.checkov.yaml`, `terraform/.checkov.baseline` |
| Images with known vulnerabilities | Trivy scans before push, results go to code scanning, plus an SBOM | `.github/actions/trivy-scan` |
| Overwritten images | Immutable ECR tags, tagged by git SHA | `modules/ecr` |
| Compromised containers | Non-root (UID 10001), read-only root filesystem, drop ALL capabilities, seccomp `RuntimeDefault`, no service account token mounted | `helm-charts/values.yaml` |
| Non-compliant pods entering the cluster | Pod Security Admission `restricted` in enforce mode | `gitops/namespaces/dev-eks.yaml` |
| Lateral movement inside the cluster | NetworkPolicy following the gRPC call graph | `helm-charts/templates/networkpolicy.yaml` |
| Over-privileged `GITHUB_TOKEN` | `contents: read` by default, extra permissions only on the jobs that need them | `.github/workflows/*` |

---

## Verification results

### Ran on Amazon EKS

The system has run on EKS in `ap-southeast-1`: Terraform built the infrastructure, CI built and pushed images to ECR over OIDC, and Argo CD synced the services into the `dev-eks` namespace. The trail is still in the Git history: every time CI pushed an image to ECR successfully, the bot committed the new tag (for example `14bc93f`, `eb86a9a`, `46e66d5` on 2026-05-04).

```bash
git log --grep='\[skip ci\]' --format='%h %ad %an %s' --date=short
```

The AWS environment was torn down afterwards to avoid cost. The security layers added later (plan/apply role split, Trivy, pod hardening, NetworkPolicy, PSA) were verified in the three ways below.

### End-to-end test on Kubernetes

A kind v0.33.0 cluster (Kubernetes 1.37), 10 images built from `src/`, the namespace created from the very same `gitops/namespaces/dev-eks.yaml`, 12 releases installed with `helm-charts/`, then both the shopping flow and attack scenarios tested. Anyone can reproduce it by following [this guide](#run-locally-with-kind).

| Scenario | Expected | Result |
|---|---|---|
| Start with the chart's default security context | 11/11 pods `Ready`, no restarts | ✅ 11/11 |
| Home page | HTTP 200 with the product catalogue | ✅ 9 products |
| Product page | Recommendations and ads shown | ✅ |
| Add to cart, view cart (Redis) | Product is in the cart | ✅ |
| Change currency | HTTP 302 | ✅ |
| Checkout (through payment, shipping, email, currency, cart) | Order confirmation page | ✅ "Your order is complete" |
| Create a pod without a security context | Rejected by PSA | ✅ Forbidden, all 4 violations listed |
| Unrelated pod → `frontend:80` | Allowed | ✅ |
| Unrelated pod → `paymentservice:50051` | Blocked | ✅ |
| Unrelated pod → `redis-cart:6379` | Blocked | ✅ |
| Unrelated pod → `productcatalogservice:3550` | Blocked | ✅ |

A complete checkout also proves that every legitimate path in the NetworkPolicy diagram is open.

### Security scans

**Checkov 3.3.22**, run with exactly the CI configuration:

| Target | Passed | Failed | Notes |
|---|---|---|---|
| Terraform | 127 | 12 | All 12 reviewed and baselined: open NACLs, EKS public endpoint, secrets not encrypted with KMS, VPC flow logs off, default security group |
| Kubernetes manifests (rendered from Helm with the `dev-eks` values) | 999 | 12 | **128** before hardening. Remaining: images not pinned by digest (11), Redis `pullPolicy` (1) |
| GitHub Actions | 371 | 5 | The `custom_tag` input of `workflow_dispatch`; low risk since only users with write access can run it |

**Trivy 0.75.0**, counting only HIGH/CRITICAL vulnerabilities that *have a fix* (vulnerability DB of 2026-10-04):

| Image | CRITICAL | HIGH | Image | CRITICAL | HIGH |
|---|---|---|---|---|---|
| adservice | 5 | 66 | frontend | 0 | 40 |
| cartservice | 0 | 4 | paymentservice | 7 | 71 |
| checkoutservice | 0 | 40 | productcatalogservice | 2 | 40 |
| currencyservice | 7 | 71 | recommendationservice | 2 | 31 |
| emailservice | 2 | 31 | shippingservice | 0 | 40 |

These vulnerabilities sit in the base images and dependencies of the original source code, so Trivy runs in report mode (`blocking: 'false'`). Changing that one line to `'true'` turns the gate on (see the [Roadmap](#roadmap)).

### Terraform

- `terraform fmt -check -recursive` and `terraform validate` both pass.
- A read-only `terraform plan` against a real AWS account with empty state: **72 resources to add, no errors, no warnings**.
- The trust policies accept exactly these `sub` claims (computed with `terraform console`):

  ```text
  github-actions-terraform-oidc-role, github-actions-ecr-oidc-role:
    repo:khaipd18/online-boutique-gitops-pipeline:ref:refs/heads/main
    repo:khaipd18@174919444/online-boutique-gitops-pipeline@1204916149:ref:refs/heads/main
  github-actions-terraform-plan-oidc-role:
    repo:khaipd18/online-boutique-gitops-pipeline:pull_request
    repo:khaipd18@174919444/online-boutique-gitops-pipeline@1204916149:pull_request
  ```

---

## Deploying to AWS

**Prerequisites:** AWS CLI with admin permissions, Terraform ≥ 1.14.8, kubectl, Helm. On GitHub, set the `AWS_ACCOUNT_ID` repository variable (Settings → Secrets and variables → Actions → Variables).

**1. Create the Terraform state backend.** S3 bucket names are globally unique. If you choose different names, update `terraform/backend.tf` and the `tf_state_bucket` and `tf_state_lock_table` variables to match.

```bash
aws s3api create-bucket --bucket <state-bucket> --region ap-southeast-1 \
  --create-bucket-configuration LocationConstraint=ap-southeast-1
aws s3api put-bucket-versioning --bucket <state-bucket> --versioning-configuration Status=Enabled
aws dynamodb create-table --table-name <lock-table> --region ap-southeast-1 \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH --billing-mode PAY_PER_REQUEST
```

**2. Build the infrastructure.** The first run has to happen locally, because the IAM roles for GitHub Actions do not exist yet. Creating EKS takes about 15–20 minutes.

```bash
cd terraform
aws sts get-caller-identity      # make sure you are in the right account
terraform init && terraform plan && terraform apply
```

**3. Install Argo CD and turn on GitOps.**

```bash
aws eks update-kubeconfig --region ap-southeast-1 --name khaipd18-eks-cluster

kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

kubectl apply -f gitops/argocd/namespaces.yaml                 # dev-eks namespace, PSA restricted
kubectl apply -f gitops/argocd/applicationset.yaml             # 10 services + Redis + frontend-external
kubectl apply -f gitops/argocd/monitoring.yaml --server-side   # Prometheus, Grafana
```

Then run the 5 *CI for … Services* workflows by hand (Actions → Run workflow) to build the images into ECR. CI updates `image.repository` and `image.tag` in `gitops/dev-eks/` on its own.

**4. Check.**

```bash
kubectl get applications -n argocd                 # Synced / Healthy
kubectl get pods -n dev-eks                        # Running
kubectl get svc frontend-external-dev -n dev-eks   # EXTERNAL-IP is the app's address
```

**5. Clean up when done.** EKS has no free tier: the control plane, EC2, the NAT Gateway and interface endpoints are all billed by the hour ([NAT Gateway pricing](https://docs.aws.amazon.com/vpc/latest/userguide/nat-gateway-pricing.html)). The load balancer created by Kubernetes is outside the Terraform state, so delete it first:

```bash
kubectl delete -f gitops/argocd/applicationset.yaml
kubectl delete svc frontend-external-dev -n dev-eks --ignore-not-found
cd terraform && terraform destroy
```

The bucket and DynamoDB table from step 1 were created by hand, so delete them separately if you no longer need them.

---

## Run locally with kind

No AWS account needed: the whole application runs with the same chart, the same security context and the same NetworkPolicies.

```bash
kind create cluster --name boutique

# Build the images for the 10 services
for s in adservice checkoutservice currencyservice emailservice frontend paymentservice \
         productcatalogservice recommendationservice shippingservice; do
  docker build -t $s:local src/$s
done
docker build -t cartservice:local src/cartservice/src
docker pull redis:8.10.2

# Load the images into the cluster
kind load docker-image --name boutique redis:8.10.2 $(for s in adservice cartservice checkoutservice \
  currencyservice emailservice frontend paymentservice productcatalogservice recommendationservice \
  shippingservice; do echo $s:local; done)

# PSA-restricted namespace, then install the 12 releases
kubectl apply -f gitops/namespaces/dev-eks.yaml
for f in gitops/dev-desktop/values-*.yaml; do
  name=$(basename "$f" .yaml); name=${name#values-}
  helm install "$name" helm-charts -f "$f" -n dev-eks
done

kubectl -n dev-eks wait --for=condition=Ready pod --all --timeout=300s
kubectl -n dev-eks port-forward svc/frontend-external 8080:8080   # open http://localhost:8080
```

> With Docker Engine 29 and the containerd image store, `kind load` may fail with `content digest … not found`. In that case, load each image with: `docker save --platform linux/amd64 <image> | docker exec -i boutique-control-plane ctr -n k8s.io images import --platform linux/amd64 -`

Clean up with `kind delete cluster --name boutique`.

---

## Day-to-day operations

- **Ship a new version of a service:** push to `src/<service>` on `main`. CI tests, builds, scans and pushes the image, the bot updates the tag, and Argo CD syncs. Nobody touches the cluster by hand.
- **Change infrastructure through a pull request:** open a PR that changes `terraform/` → Checkov runs, then `terraform plan` with the read-only role (`-lock=false`) → review the plan in the log → merge into `main` → `terraform apply` with the admin role. PRs from forks get no OIDC token from GitHub, so only Checkov runs for them.
- **Branch protection:** enable a ruleset on `main` (pull request required, *Checkov Scan* must pass). Note that the CI bot pushes image tags straight to `gitops/`, so either let GitHub Actions bypass the rule or switch the bot to opening PRs.
- **Accept a new Checkov finding:** fix the configuration first. If the finding is judged acceptable, regenerate the baseline in a PR so it gets reviewed:
  `checkov --config-file .checkov.yaml -d terraform --framework terraform --create-baseline`
- **Switch AWS accounts:** repeat steps 1–3 of the deployment and change `AWS_ACCOUNT_ID`. If the account is shared with another project, check for name clashes first: an account can only have one OIDC provider for `token.actions.githubusercontent.com`, and IAM role and policy names are unique within an account.

---

## Roadmap

What comes next, in order of priority:

- [ ] Upgrade the services' dependencies (possibly automated with Dependabot), then set `blocking: 'true'` for Trivy, `govulncheck` and `npm audit`.
- [ ] Restrict the EKS public endpoint (currently open to `0.0.0.0/0`) or move to a private endpoint only.
- [ ] Narrow `ecr-endpoint-sg` from all protocols down to `tcp/443` from the VPC (found while drawing the LLD security group page).
- [ ] One NAT Gateway per AZ for production (one shared NAT today to save cost).
- [ ] Centralised secret management with External Secrets Operator + AWS Secrets Manager.
- [ ] Pin images by digest, sign them with cosign and verify at admission.
- [ ] Replace the default Classic Load Balancer with the AWS Load Balancer Controller (NLB/ALB).
- [ ] Add staging/production environments with a promotion flow, and canary releases with Argo Rollouts.
- [ ] SLO-based alert rules and Grafana dashboards for every service.
- [ ] Consider native S3 state locking instead of DynamoDB.

---

## Repository layout

```text
online-boutique-gitops-pipeline/
├── .github/
│   ├── actions/trivy-scan/   # Composite action: image scan, SARIF, SBOM
│   └── workflows/            # Per-language CI, Terraform, Security Scan
├── docs/infrastructure/      # HLD/LLD diagrams (draw.io + YAML spec + PNG)
├── gitops/
│   ├── argocd/               # ApplicationSet, namespace app, monitoring
│   ├── namespaces/           # dev-eks namespace (Pod Security Admission)
│   ├── dev-eks/              # Helm values for EKS
│   └── dev-desktop/          # Helm values for local Kubernetes
├── helm-charts/              # Universal chart shared by every service
├── k8s-manifests/            # Kustomize base/overlays (early stage, not used by Argo CD)
├── terraform/                # Modules: vpc, eks, ecr, vpc-endpoints, github-oidc-role
├── src/, protos/             # Original Online Boutique source code
└── .checkov.yaml             # Shared Checkov configuration
```

---

## References and credits

- Application: Google Cloud Platform, [Online Boutique (microservices-demo)](https://github.com/GoogleCloudPlatform/microservices-demo), Apache License 2.0. The code in `src/` and `protos/` belongs to the original project.
- AWS: [GitHub OIDC trust policy](https://docs.aws.amazon.com/IAM/latest/UserGuide/id_roles_create_for-idp_oidc.html) · [IRSA](https://docs.aws.amazon.com/eks/latest/best-practices/identity-and-access-management.html) · [EKS network policy](https://docs.aws.amazon.com/eks/latest/userguide/cni-network-policy-configure.html) · [ECR VPC endpoints](https://docs.aws.amazon.com/AmazonECR/latest/userguide/vpc-endpoints.html) · [ECR tag immutability](https://docs.aws.amazon.com/AmazonECR/latest/userguide/image-tag-mutability.html) · [Registry-level scanning](https://docs.aws.amazon.com/AmazonECR/latest/APIReference/API_PutImageScanningConfiguration.html) · [ReadOnlyAccess](https://docs.aws.amazon.com/IAM/latest/UserGuide/access_policies_job-functions.html)
- GitHub: [OpenID Connect reference](https://docs.github.com/en/actions/reference/security/oidc) (`sub` claim formats, including the immutable one)
- Kubernetes: [Pod Security Standards](https://kubernetes.io/docs/concepts/security/pod-security-standards/) · [Network Policies](https://kubernetes.io/docs/concepts/services-networking/network-policies/)
- Argo CD: [Sync Options](https://argo-cd.readthedocs.io/en/stable/user-guide/sync-options/)
