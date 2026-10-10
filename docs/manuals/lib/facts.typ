// Facts shared by every manual and both languages. Values mirror terraform/, gitops/, helm-charts/
// and .github/; update them here when the source changes, then rebuild with ../build.sh.

#let repo-url = "https://github.com/khaipd18/online-boutique-gitops-pipeline"
#let region = "ap-southeast-1"
#let cluster = "khaipd18-eks-cluster"
#let namespace = "dev-eks"
#let state-bucket = "khaipd18-obe-tf-state-445817183958"
#let state-key = "dev/terraform.tfstate"
#let lock-table = "khaipd18-devops-project-terraform-state-lock"
#let doc-date = "2026-10-10"

// Tool and component versions pinned in the repository
#let versions = (
  ("Terraform", "1.14.8", "terraform.yaml, README"),
  ("AWS provider", "6.39.0", "terraform/versions.tf"),
  ("Kubernetes (EKS)", "1.35", "terraform/variables.tf"),
  ("VPC CNI add-on", "v1.21.1-eksbuild.7", "terraform/variables.tf"),
  ("CoreDNS add-on", "v1.13.2-eksbuild.4", "terraform/variables.tf"),
  ("kube-proxy add-on", "v1.35.3-eksbuild.2", "terraform/variables.tf"),
  ("Metrics Server add-on", "v0.9.0-eksbuild.11", "terraform/variables.tf"),
  ("kube-prometheus-stack", "84.4.0", "gitops/argocd/monitoring.yaml"),
  ("Argo CD", "stable manifest", "README, step 3"),
  ("Checkov", "3.3.22", ".github/workflows/*"),
  ("Trivy", "0.75.0", ".github/actions/trivy-scan"),
  ("Redis (cart store)", "8.10.2", "gitops/dev-eks/values-redis-cart.yaml"),
)

// Network plan: cidrsubnet(10.18.0.0/16, 8, n)
#let vpc-cidr = "10.18.0.0/16"
#let subnets = (
  ("public (az1)", "apse1-az1", "10.18.0.0/24", "NAT Gateway, load balancer"),
  ("public (az2)", "apse1-az2", "10.18.1.0/24", "load balancer"),
  ("private (az1)", "apse1-az1", "10.18.2.0/24", "EKS nodes, interface endpoints"),
  ("private (az2)", "apse1-az2", "10.18.3.0/24", "EKS nodes, interface endpoints"),
)

// Workloads deployed by the ApplicationSet (release = <name>-dev in namespace dev-eks).
// (release, language, service port -> container port, allowed callers, cpu req/limit, memory req/limit)
#let services = (
  ("frontend", "Go", "80 → 8080", "any (LoadBalancer)", "100m / 200m", "64Mi / 256Mi"),
  ("checkoutservice", "Go", "5050", "frontend", "100m / 200m", "64Mi / 128Mi"),
  ("productcatalogservice", "Go", "3550", "frontend, checkout, recommendation", "100m / 200m", "64Mi / 128Mi"),
  ("shippingservice", "Go", "50051", "frontend, checkout", "100m / 200m", "64Mi / 128Mi"),
  ("cartservice", "C#", "7070", "frontend, checkout", "200m / 300m", "64Mi / 128Mi"),
  ("adservice", "Java", "9555", "frontend", "200m / 300m", "180Mi / 300Mi"),
  ("currencyservice", "Node.js", "7000", "frontend, checkout", "100m / 200m", "64Mi / 128Mi"),
  ("paymentservice", "Node.js", "50051", "checkout", "100m / 200m", "64Mi / 128Mi"),
  ("emailservice", "Python", "8080", "checkout", "100m / 200m", "64Mi / 128Mi"),
  ("recommendationservice", "Python", "8080", "frontend", "100m / 200m", "250Mi / 500Mi"),
  ("redis-cart", "Redis", "6379", "cartservice", "100m / 200m", "64Mi / 128Mi"),
)

// GitHub Actions roles (trust = sub claim after repo:<repo>:)
#let roles = (
  ("github-actions-ecr-oidc-role", "ref:refs/heads/main", "GitHubActions-ECR-Push-Policy (push/pull on the 10 repositories)"),
  ("github-actions-terraform-plan-oidc-role", "pull_request", "ReadOnlyAccess + GitHubActions-Terraform-State-Read-Policy"),
  ("github-actions-terraform-oidc-role", "environment:production", "AdministratorAccess + GitHubActions-Terraform-State-Policy"),
)

// CI quality gates per stack: (stack, lint/format, test, dependency scan)
#let gates = (
  ("Go (4 services)", "golangci-lint v1.64.8 (blocking)", "go test (blocking)", "govulncheck v1.8.0 (warning)"),
  (".NET (cartservice)", "dotnet format (warning)", "dotnet test (blocking)", "dotnet list package --vulnerable (blocking)"),
  ("Java (adservice)", "google-java-format (warning)", "gradle test (blocking)", "–"),
  ("Node.js (2 services)", "ESLint 8 (blocking)", "–", "npm audit (warning)"),
  ("Python (2 services)", "flake8 (blocking)", "pytest (blocking when tests exist)", "bandit (blocking)"),
)

// AWS documentation used as sources
#let src = (
  oidc-role: "https://docs.aws.amazon.com/IAM/latest/UserGuide/id_roles_create_for-idp_oidc.html",
  irsa: "https://docs.aws.amazon.com/eks/latest/best-practices/identity-and-access-management.html",
  pod-identity: "https://docs.aws.amazon.com/eks/latest/userguide/pod-identities.html",
  netpol: "https://docs.aws.amazon.com/eks/latest/userguide/cni-network-policy-configure.html",
  ecr-endpoints: "https://docs.aws.amazon.com/AmazonECR/latest/userguide/vpc-endpoints.html",
  ecr-immutable: "https://docs.aws.amazon.com/AmazonECR/latest/userguide/image-tag-mutability.html",
  ecr-scanning: "https://docs.aws.amazon.com/AmazonECR/latest/APIReference/API_PutImageScanningConfiguration.html",
  metrics-server: "https://docs.aws.amazon.com/eks/latest/userguide/metrics-server.html",
  regional-nat: "https://docs.aws.amazon.com/vpc/latest/userguide/nat-gateways-regional.html",
  nat-pricing: "https://docs.aws.amazon.com/vpc/latest/userguide/nat-gateway-pricing.html",
  endpoint: "https://docs.aws.amazon.com/eks/latest/userguide/cluster-endpoint.html",
  versions: "https://docs.aws.amazon.com/eks/latest/userguide/kubernetes-versions.html",
  access-config: "https://docs.aws.amazon.com/eks/latest/APIReference/API_CreateAccessConfigRequest.html",
  access-entries: "https://docs.aws.amazon.com/eks/latest/userguide/create-standard-access-entry-policy.html",
  inbound: "https://docs.aws.amazon.com/prescriptive-guidance/latest/load-balancer-stickiness/subnets-routing.html",
  envelope: "https://docs.aws.amazon.com/eks/latest/userguide/envelope-encryption.html",
  logs-encryption: "https://docs.aws.amazon.com/AmazonCloudWatch/latest/logs/data-protection.html",
  nodegroup-update: "https://docs.aws.amazon.com/eks/latest/userguide/update-managed-node-group.html",
)

// Figures exported from docs/infrastructure (paths are relative to the repository root, see build.sh)
#let fig = (
  hld: "/docs/infrastructure/images/aws-architecture.png",
  network: "/docs/infrastructure/images/aws-lld-network-detail.png",
  sg: "/docs/infrastructure/images/aws-lld-security-groups.png",
  cicd: "/docs/infrastructure/images/aws-lld-cicd-iam-state.png",
  pipeline: "/docs/infrastructure/images/aws-delivery-pipeline.png",
  traffic: "/docs/infrastructure/images/aws-in-cluster-traffic.png",
)
