# Online Boutique - EKS GitOps & CI/CD Pipeline

## 📝 Tổng quan dự án

Dự án triển khai luồng End-to-End DevOps Pipeline cho kiến trúc Microservices. Hệ thống được tổ chức theo mô hình **Monorepo**, quản lý tập trung từ source code ứng dụng, Infrastructure as Code (IaC) đến Kubernetes manifests.

Mục tiêu của dự án là thiết lập các tiêu chuẩn vận hành:
* Khởi tạo hạ tầng AWS bằng **Infrastructure as Code**.
* Tự động hóa tích hợp liên tục (CI) để build và push image.
* Triển khai liên tục theo mô hình **Pull-based GitOps**, đồng bộ trạng thái thực tế của cluster với source code.

### 📦 Nguồn gốc ứng dụng
Dự án sử dụng source code từ [**Google Cloud Microservices Demo (Online Boutique)**](https://github.com/GoogleCloudPlatform/microservices-demo). Đây là hệ thống e-commerce gồm 11 microservices, viết bằng nhiều ngôn ngữ và giao tiếp qua gRPC, được sử dụng làm cơ sở để triển khai và kiểm thử quy trình CI/CD trên EKS.

---

## 🏗️ Kiến trúc hệ thống

Hệ thống tuân thủ nguyên tắc IaC và GitOps.

### 🔄 Luồng CI/CD
1. **Developer** push code thay đổi lên GitHub (Monorepo).
2. **GitHub Actions** nhận diện thay đổi, trigger luồng build tương ứng và push Docker Image lên **Amazon ECR**.
3. **Terraform** duy trì cấu hình hạ tầng AWS (VPC, EKS, IAM).
4. **Argo CD** (chạy bên trong EKS) monitor thư mục manifests trên Git và tự động đồng bộ bản cập nhật xuống Cluster.

### 🛡️ Tính năng bảo mật và vận hành
* **Zero-trust Authentication:** Dùng OIDC cấp quyền IAM cho Pod thông qua IRSA, không sử dụng long-lived credentials.
* **Least-privilege CI/CD:** Pull request chỉ được `terraform plan` bằng role read-only; `terraform apply` và push image chỉ được phép từ nhánh `main` (khóa bằng claim `sub` trong IAM trust policy).
* **Supply chain security:** Mọi image được quét bằng Trivy trước khi push (kết quả lên tab *Security* của GitHub, kèm SBOM CycloneDX); Checkov chặn thay đổi Terraform có lỗi cấu hình mới trước khi plan/apply.
* **Pod hardening:** Pod chạy non-root, read-only root filesystem, drop mọi Linux capability, seccomp `RuntimeDefault`; namespace áp Pod Security Admission mức `restricted`.
* **Network segmentation:** Mỗi service có NetworkPolicy chỉ cho phép đúng các service gọi tới nó (VPC CNI bật network policy).
* **Auto Self-healing:** Cấu hình GitOps trên Argo CD tự động ghi đè các thay đổi thủ công trên cluster về trạng thái định nghĩa trong Git.

---

## 📁 Cấu trúc Monorepo

```text
online-boutique-gitops-pipeline/
├── .github/workflows/   # CI pipeline đa ngôn ngữ (Go, .NET, Node...) và luồng Terraform
├── gitops/              # Cấu hình Argo CD (ApplicationSet) và values.yaml cho từng môi trường
├── helm-charts/         # Universal Helm Chart dùng chung cho 11 microservices
├── k8s-manifests/       # Kustomize (base & overlays)
├── protos/              # Protocol Buffers định nghĩa giao tiếp gRPC
├── src/                 # Source code 11 microservices
├── terraform/           # IaC khởi tạo hạ tầng AWS (Modular)
├── .gitignore           
└── README.md
```
## 🔍 Chi tiết kỹ thuật

### 🏗️ Infrastructure as Code (Terraform)

Tài nguyên hạ tầng AWS được quản lý bằng Terraform theo kiến trúc Modular.

<details>
<summary><b>Chi tiết cấu trúc Terraform</b></summary>
<br>

#### 📦 Phân chia Module
* **`vpc`**: Setup mạng nền tảng (VPC, Subnets, Route Tables).
* **`eks`**: Cấu hình EKS Cluster, Control Plane và Worker Node Groups.
* **`ecr`**: Cấu hình container registry và scan lỗ hổng bảo mật khi push.
* **`vpc-endpoints`**: Thiết lập PrivateLink đến các dịch vụ AWS.
* **`github-oidc-role`**: Quản lý định danh và IAM role cho CI/CD pipeline.

#### 🔌 EKS Add-ons
Sử dụng AWS Managed Add-ons cho các core components:
* **VPC CNI**: Cấp phát IP từ VPC cho Pod.
* **CoreDNS**: Xử lý Service Discovery.
* **Kube-proxy**: Định tuyến traffic giữa các service.

#### 🔐 VPC Endpoints (AWS PrivateLink)
Thiết lập kiến trúc semi-air-gapped cho Worker Nodes trong Private Subnet giao tiếp với AWS services:
* **ECR (API & Docker)**: Pull image nội bộ.
* **S3 Gateway**: Truy cập S3 lưu trữ image layers.
* **STS**: Hỗ trợ xác thực **IRSA**.

#### 🆔 Xác thực OIDC cho GitHub Actions
Loại bỏ Access/Secret Keys tĩnh:
* Dùng **OIDC** thiết lập trust relationship giữa GitHub và AWS.
* **Trust Policy** giới hạn truy cập theo repo `khaipd18/online-boutique-gitops-pipeline`.

#### 💾 Quản lý Terraform State
Dùng **Remote Backend** quản lý state file:
* **S3 Standard Backend**: Lưu trữ file `.tfstate`.
* **DynamoDB State Locking**: Khóa state để tránh Race Condition khi chạy concurrent pipelines.
</details>

### ☸️ Quản lý cấu hình Kubernetes (Manifests, Kustomize & Helm)

Quản lý cấu hình được thực hiện qua 3 phương pháp: Custom Manifests, Kustomize và Helm.

<details>
<summary><b>Chi tiết triển khai cấu hình Kubernetes</b></summary>
<br>

#### 📜 Giai đoạn phát triển
1. **Custom Manifests:** Viết K8s primitives (Deployment, Service, ServiceAccount) cho 11 services. Cấp phát Resource Limits/Requests độc lập.
2. **Kustomize Integration:** Sử dụng để giảm lặp code (DRY). Tách biệt `base/` (config tĩnh) và `overlays/` (config override theo môi trường).
3. **Helm Charts:** Đóng gói thành template động (Dynamic Templating) hỗ trợ versioning và rollback.

#### 📂 Cấu hình đa môi trường
* **`local-dev`**: Thêm prefix `local-`, set `imagePullPolicy: Never` để dùng image local, patch địa chỉ service tương ứng.
* **`aws-dev`**: Thêm prefix `aws-dev-`, map image sang ECR, patch địa chỉ service, expose `frontend-external` (LoadBalancer) ở port 80 → 8080.

#### 📦 Universal Helm Chart
Sử dụng một **Universal Chart** thay vì duy trì nhiều chart ròi rạc:
* **`templates/`**: Chứa core resources (`deployment.yaml`, `service.yaml`, `serviceaccount.yaml`) render bằng Go Template.
* **`values.yaml`**: Giá trị mặc định của chart; override theo từng service/môi trường nằm ở `gitops/<env>/values-<service>.yaml` (Image Tag, Port, Limits...).
* **`Chart.yaml`**: Quản lý metadata và versioning.
</details>

### ⚙️ CI Pipeline với GitHub Actions

Pipeline CI hỗ trợ kiến trúc Polyglot Monorepo.

<details>
<summary><b>Chi tiết luồng CI và GitOps Push-back</b></summary>
<br>

#### 🧠 Smart Build Trigger
Pipeline chỉ build các thành phần có sự thay đổi source code:
* **Language-specific Workflows:** Tách luồng CI theo stack (`dotnet`, `go`, `java`, `node`, `py`).
* **Path Filtering & Dynamic Matrix:** Dùng `dorny/paths-filter` nhận diện directory bị thay đổi. Cấu hình matrix động để cấp phát job song song.

#### 🛡️ Quality Gates
Các step kiểm tra code trước khi build:
* **Linting/Formatting:** Check chuẩn code format (vd: `dotnet format`).
* **Security Scanning:** Scan lỗ hổng bảo mật package dependencies.
* **Unit Testing:** Thực thi test tự động.
* **Image Scanning (Trivy):** Composite action `.github/actions/trivy-scan` quét image trước khi push, đẩy lỗ hổng HIGH/CRITICAL lên GitHub code scanning và lưu SBOM làm artifact. Hiện ở chế độ báo cáo (`blocking: 'false'`) vì dependency của các service chưa được nâng cấp; đổi thành `'true'` để chặn.

#### 🔐 OIDC Authentication
Runner của GitHub Actions dùng **OIDC** lấy token tạm thời từ AWS IAM để login ECR.

#### 🔄 GitOps Push-back Loop
Sau khi quá trình build và push ECR hoàn tất, pipeline tự động thực hiện:
1. Dùng `yq` update Git SHA tag vào file `values.yaml` của service tương ứng.
2. Bot tự động commit và push config ngược lại repo.
3. **Retry Loop:** Xử lý race condition (git push conflict) khi nhiều service trigger build đồng thời.

#### 🏗️ Terraform CI/CD
Pipeline tự động hóa quản lý hạ tầng:
* `fmt` và `validate` check cú pháp.
* Generate `terraform plan` khi tạo Pull Request.
* Chạy `terraform apply` khi merge vào nhánh main.
</details>

### 🐙 Continuous Deployment với Argo CD

Luồng CD được triển khai bằng Argo CD theo mô hình Pull-based GitOps.

<details>
<summary><b>Chi tiết cấu hình Argo CD</b></summary>
<br>

#### 🧩 ApplicationSet Provisioning
Sử dụng **ApplicationSet** + List Generator quét danh sách services (`adservice`, `frontend`...) để động sinh ra các bản release, tự động map `{{name}}` vào `values-{{name}}.yaml`.

#### 🌍 Override theo môi trường
Định nghĩa hành vi qua file values:
* **`dev-desktop` (Docker Desktop):** Set `imagePullPolicy: Never` để sử dụng image trong local Docker cache.
* **`dev-eks` (AWS Cloud):** Set `imagePullPolicy: Always` để đảm bảo Node kéo image mới nhất từ ECR.

#### 🚦 Decoupling với `frontend-external`
Expose ứng dụng ra LoadBalancer:
* Set `deployment.enabled: false` để chỉ render Service, không tạo Deployment/Pod mới.
* Dùng `selectorOverride: "frontend-dev"` map Service Type LoadBalancer vào các Pods của release `frontend-dev` nội bộ.

#### 📊 Monitoring Stack (kube-prometheus-stack)
Triển khai Prometheus & Grafana stack. Sử dụng `ServerSideApply=true` để bypass giới hạn dung lượng annotation của K8s khi apply file CRDs.
</details>

## 🚀 Hướng dẫn Cài đặt & Triển khai (Step-by-step Deployment)
### 📋 Yêu cầu hệ thống
* **AWS CLI** (Đã login account có quyền Admin để tạo VPC, EKS, IAM).
* **Terraform CLI** (v1.14.8+).
* **kubectl**.

---

### Bước 1: Khởi tạo hạ tầng AWS

Vào thư mục `terraform` và provision hạ tầng:

```bash
cd terraform
terraform init
terraform plan
terraform apply -auto-approve
```

> *(Quá trình tạo EKS mất khoảng 15–20 phút).*

---

### Bước 2: Cấu hình kết nối Kubernetes (Kubeconfig)

Cấu hình kubectl kết nối với EKS:

```bash
aws eks update-kubeconfig --region ap-southeast-1 --name khaipd18-eks-cluster
kubectl get nodes
```

> **💡Troubleshooting:**
> Nếu gặp lỗi the server has asked for the client to provide credentials, token AWS CLI có thể đã hết hạn. Chạy lại aws configure hoặc refresh SSO session.

---

### Bước 3: Cài đặt Argo CD

Cài đặt Argo CD trực tiếp vào cụm EKS để chuẩn bị cho luồng kéo (pull) cấu hình:

```bash
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
```

---

### Bước 4: Kích hoạt luồng GitOps & Monitoring

Apply ApplicationSet:

```bash
cd ..
# Namespace dev-eks với Pod Security Admission "restricted"
kubectl apply -f gitops/argocd/namespaces.yaml

# Deploy 11 Microservices
kubectl apply -f gitops/argocd/applicationset.yaml

# Deploy Prometheus & Grafana
kubectl apply -f gitops/argocd/monitoring.yaml --server-side
```

---

### Bước 5: Kiểm tra ứng dụng và Truy cập (Verification)

Argo CD sẽ mất vài phút để kéo Image và khởi tạo Pods. Kiểm tra trạng thái sync của Argo CD:

```bash
kubectl get pods -n dev-eks
```

Khi tất cả các Pod đã ở trạng thái `Running`, lấy địa chỉ truy cập ứng dụng từ LoadBalancer của Frontend:

```bash
kubectl get svc frontend-external-dev -n dev-eks
```

Sử dụng URL ở cột EXTERNAL-IP để truy cập Online Boutique.

---

### 🔄 Day-2 Operations

Sau khi setup ban đầu, hệ thống tự động xử lý các luồng:

- **Dev:** Push code mới vào thư mục `src/<service-name>`.
- **CI Pipeline:** Thực hiện test, build, push image và update tag vào thư mục `gitops/`.
- **CD Pipeline:** Argo CD detect tag mới và sync bản release lên EKS.

---

### 🔀 Quy trình thay đổi hạ tầng qua Pull Request

1. Tạo branch, sửa `terraform/`, mở Pull Request vào `main`.
2. Workflow *Terraform CI/CD Pipeline* chạy Checkov (chặn nếu có lỗi cấu hình mới so với `terraform/.checkov.baseline`), sau đó `terraform plan` bằng role read-only `github-actions-terraform-plan-oidc-role`. PR từ fork không được cấp OIDC token nên chỉ chạy Checkov.
3. Review plan trong log của workflow, merge vào `main` → `terraform apply` bằng role `github-actions-terraform-oidc-role` (chỉ assume được từ `main`).

Nên bật branch protection cho `main` (Settings → Rules → Rulesets): bắt buộc qua Pull Request và yêu cầu check *Checkov Scan* pass. Lưu ý bot CI đang push thẳng tag image vào `gitops/` trên `main`: cần cho GitHub Actions bypass rule đó, hoặc đổi bot sang mở Pull Request.

---

### 🔁 Chuyển sang AWS account khác

Account ID không hardcode trong code: workflow đọc từ repository variable `AWS_ACCOUNT_ID` (nếu chưa đặt thì dùng account cũ `797226340543`), Terraform lấy account từ credentials đang dùng.

1. **Tạo state backend** trong account mới (S3 bucket + DynamoDB lock table). Tên bucket S3 là duy nhất toàn cầu; nếu đổi tên thì sửa `terraform/backend.tf` và biến `tf_state_bucket` / `tf_state_lock_table` trong `terraform/variables.tf` cho khớp.

   ```bash
   aws s3api create-bucket --bucket <state-bucket> --region ap-southeast-1 \
     --create-bucket-configuration LocationConstraint=ap-southeast-1
   aws s3api put-bucket-versioning --bucket <state-bucket> --versioning-configuration Status=Enabled
   aws dynamodb create-table --table-name <lock-table> --region ap-southeast-1 \
     --attribute-definitions AttributeName=LockID,AttributeType=S \
     --key-schema AttributeName=LockID,KeyType=HASH --billing-mode PAY_PER_REQUEST
   ```

2. **Apply Terraform lần đầu từ máy local** bằng credentials admin của account mới. Lần đầu bắt buộc chạy local vì các IAM role OIDC cho GitHub Actions chưa tồn tại:

   ```bash
   cd terraform
   aws sts get-caller-identity   # kiểm tra đúng account trước khi apply
   terraform init
   terraform plan
   terraform apply
   ```

3. **Đặt repository variable** `AWS_ACCOUNT_ID` = account mới (Settings → Secrets and variables → Actions → Variables).

4. Làm tiếp **Bước 2 → Bước 5** ở trên (kubeconfig, Argo CD, ApplicationSet).

5. **Chạy tay cả 5 workflow CI** (Actions → *CI for … Services* → Run workflow) để build và push image lên ECR mới. CI tự ghi lại `image.repository` và `image.tag` trong `gitops/dev-eks/values-*.yaml`, nên không cần sửa tay URL ECR.

> `k8s-manifests/overlays/aws-dev` (Kustomize, không được Argo CD sử dụng) vẫn ghi ECR của account cũ.

---

