#import "lib/template.typ": manual, callout, palette, playbook as playbook-table
#import "lib/facts.typ" as facts

#let note = callout.with("note", lang: "vi")
#let warning = callout.with("warning", lang: "vi")
#let important = callout.with("important", lang: "vi")
#let tip = callout.with("tip", lang: "vi")
#let playbook = playbook-table.with(([Triệu chứng], [Nguyên nhân thường gặp], [Chẩn đoán], [Xử lý]))

#set heading(supplement: [Mục])
#set figure(supplement: it => if it.func() == table { [Bảng] } else { [Hình] })

#show: manual.with(
  title: "Sổ tay vận hành",
  subtitle: "Triển khai, vận hành hằng ngày và xử lý sự cố",
  doc-id: "OBE-RUN-001-VI",
  version: "1.0",
  date: facts.doc-date,
  status: "Đã duyệt cho môi trường dev",
  owner: "khaipd18 (DevOps / Cloud)",
  audience: "Kỹ sư triển khai, vận hành hoặc hỗ trợ nền tảng",
  classification: "Nội bộ",
  repository: facts.repo-url,
  lang: "vi",
  revisions: (
    ("1.0", facts.doc-date, "Phát hành lần đầu: truy cập, bootstrap, quy trình thường ngày, monitoring, xử lý sự cố, gỡ môi trường.", "khaipd18"),
  ),
  related: (
    [OBE-TDD-001-VI Tài liệu thiết kế kỹ thuật (`docs/manuals/technical-design.vi.pdf`)],
    [Bản tiếng Anh của sổ tay này: `docs/manuals/operations-runbook.en.pdf` (OBE-RUN-001)],
    [README.vi.md: tóm tắt dự án và hướng dẫn chạy thử với kind],
  ),
)

= Về sổ tay này

== Mục đích và cách dùng

Sổ tay này hướng dẫn kỹ sư triển khai và vận hành nền tảng Online Boutique: các quy trình làm một lần (bootstrap, gỡ môi trường, chuyển tài khoản), các thay đổi thường ngày (ra bản mới, rollback, đổi cấu hình, đổi hạ tầng) và cách xử lý khi có sự cố. Thiết kế đằng sau được mô tả trong Tài liệu thiết kế kỹ thuật (OBE-TDD-001-VI).

Mỗi quy trình ghi điều kiện cần, các bước đánh số và bước kiểm tra kết quả. Làm theo đúng thứ tự. Các lệnh giả định chạy bằng Bash tại thư mục gốc của repository.

#important[Git là nguồn sự thật duy nhất. Argo CD đưa mọi thay đổi tay bằng `kubectl` trong namespace #raw(facts.namespace) về lại như cũ (self-heal). Ngoài các lệnh chẩn đoán trong sổ tay này, hãy thay đổi cluster qua pull request.]

== Thông tin môi trường

#table(
  columns: (30%, 1fr),
  [Mục], [Giá trị],
  [Region], [#raw(facts.region)],
  [EKS cluster], [#raw(facts.cluster) (Kubernetes 1.35)],
  [Namespace ứng dụng], [#raw(facts.namespace) (release `<service>-dev`)],
  [Namespace khác], [`argocd` (Argo CD), `monitoring` (kube-prometheus-stack)],
  [Điểm vào public], [Service `frontend-external-dev` (Classic Load Balancer, port 80)],
  [Terraform state], [S3 #raw(facts.state-bucket), key #raw(facts.state-key); bảng khóa #raw(facts.lock-table)],
  [Repository], [#link(facts.repo-url)],
  [Kiểm soát trên GitHub], [Ruleset `protect-main`; environment `production` (người duyệt `khaipd18`)],
)

== Mức độ nghiêm trọng

#table(
  columns: (10%, 30%, 1fr, 20%),
  [Mức], [Định nghĩa], [Ví dụ], [Phản hồi],
  [SEV1], [Shop không truy cập được hoặc checkout hỏng với mọi người dùng], [`frontend` sập, mất load balancer, mọi pod đều lỗi], [Xử lý ngay; ưu tiên sửa hoặc rollback, điều tra sau],
  [SEV2], [Một tính năng bị suy giảm, hoặc luồng triển khai bị chặn], [Một service crash liên tục, CI không push được image, Argo CD bị kẹt], [Trong ngày làm việc],
  [SEV3], [Không ảnh hưởng người dùng], [Finding scan mức warning, một pod khởi động lại, tài liệu lệch với thực tế], [Đưa vào kế hoạch thường ngày],
)

Nền tảng có một người phụ trách duy nhất (`khaipd18`). Mọi sự cố SEV1/SEV2 được ghi lại thành GitHub issue, gồm diễn biến, nguyên nhân và việc cần làm tiếp.

= Truy cập và công cụ

== Công cụ trên máy làm việc

#table(
  columns: (28%, 1fr),
  [Công cụ], [Dùng để],
  [AWS CLI v2], [Credential, kubeconfig, backend state, kiểm tra trên AWS],
  [Terraform 1.14.8], [Hạ tầng (chỉ cho lần apply đầu và trường hợp khẩn cấp; bình thường do CI chạy)],
  [`kubectl`, Helm], [Kiểm tra cluster; cài Argo CD],
  [GitHub CLI (`gh`)], [Xem run, log, duyệt deployment, cài đặt repository],
  [Typst], [Build lại các tài liệu PDF này (`docs/manuals/build.sh`)],
)

== Kết nối tới AWS và cluster

+ Kiểm tra danh tính AWS và tài khoản đang dùng:
  ```bash
  aws sts get-caller-identity
  ```
+ Ghi cấu hình kubeconfig:
  ```bash
  aws eks update-kubeconfig --region ap-southeast-1 --name khaipd18-eks-cluster
  kubectl get nodes
  ```

#note[Cluster không đặt `access_config` nên áp dụng mặc định của API: ban đầu chỉ IAM principal đã tạo cluster có quyền admin #link(facts.src.access-config)[[AWS]]. Kiểm tra chế độ bằng `aws eks describe-cluster --name khaipd18-eks-cluster --query cluster.accessConfig`. Muốn cấp quyền cho kỹ sư khác, chuyển cluster sang `API_AND_CONFIG_MAP` rồi tạo access entry kèm access policy #link(facts.src.access-entries)[[AWS]]; nên làm bằng Terraform để không bị mất ở lần apply sau.]

== Mở các giao diện quản trị

Mọi giao diện đều truy cập qua `kubectl port-forward`; không giao diện nào mở ra internet.

```bash
# Argo CD: https://localhost:8080, user admin
kubectl -n argocd port-forward svc/argocd-server 8080:443
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath='{.data.password}' | base64 -d; echo

# Grafana: http://localhost:3000, user admin
kubectl -n monitoring port-forward svc/kube-prometheus-stack-grafana 3000:80
kubectl -n monitoring get secret kube-prometheus-stack-grafana \
  -o jsonpath='{.data.admin-password}' | base64 -d; echo

# Prometheus: http://localhost:9090
kubectl -n monitoring port-forward svc/kube-prometheus-stack-prometheus 9090:9090

# Địa chỉ shop
kubectl -n dev-eks get svc frontend-external-dev \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'; echo
```

Đổi mật khẩu admin của Argo CD sau lần đăng nhập đầu tiên và xóa `argocd-initial-admin-secret`.

= Quy trình làm một lần

== RB-01 Dựng môi trường mới

*Khi nào:* lần triển khai đầu tiên trên một tài khoản AWS, hoặc dựng lại sau khi đã gỡ. *Thời gian:* khoảng 45 phút (tạo EKS mất 15–20 phút). *Chi phí:* bắt đầu tính theo giờ từ bước 4 (xem RB-13).

+ *Đặt tài khoản đích trên GitHub.* Settings → Secrets and variables → Actions → Variables → `AWS_ACCOUNT_ID`. Hoặc:
  ```bash
  gh variable set AWS_ACCOUNT_ID --body <account-id>
  ```
+ *Kiểm tra trùng tên* nếu tài khoản dùng chung: mỗi tài khoản chỉ có một OIDC provider cho `token.actions.githubusercontent.com`, và tên IAM role, policy là duy nhất trong tài khoản (`github-actions-*`, `GitHubActions-*`).
+ *Tạo backend lưu state* (một lần cho mỗi tài khoản). Tên bucket là duy nhất toàn cầu; nếu đổi tên thì sửa cả `terraform/backend.tf` và các biến `tf_state_bucket` / `tf_state_lock_table`.
  ```bash
  aws s3api create-bucket --bucket <state-bucket> --region ap-southeast-1 \
    --create-bucket-configuration LocationConstraint=ap-southeast-1
  aws s3api put-bucket-versioning --bucket <state-bucket> \
    --versioning-configuration Status=Enabled
  aws dynamodb create-table --table-name <lock-table> --region ap-southeast-1 \
    --attribute-definitions AttributeName=LockID,AttributeType=S \
    --key-schema AttributeName=LockID,KeyType=HASH --billing-mode PAY_PER_REQUEST
  ```
+ *Apply lần đầu từ máy local.* Lúc này các role cho GitHub chưa tồn tại nên CI chưa làm được. Danh tính dùng ở bước này sẽ trở thành admin của cluster.
  ```bash
  cd terraform
  aws sts get-caller-identity          # phải đúng tài khoản đích
  terraform init
  terraform plan -out tfplan           # khoảng 73 resource sẽ được tạo
  terraform apply tfplan
  ```
+ *Cài Argo CD và các ứng dụng:*
  ```bash
  aws eks update-kubeconfig --region ap-southeast-1 --name khaipd18-eks-cluster
  kubectl create namespace argocd
  kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
  kubectl apply -f gitops/argocd/namespaces.yaml
  kubectl apply -f gitops/argocd/applicationset.yaml
  kubectl apply -f gitops/argocd/monitoring.yaml --server-side
  ```
+ *Build image.* Chạy 5 workflow CI một lần (Actions → CI for … Services → Run workflow), hoặc:
  ```bash
  for w in go dotnet java node py; do gh workflow run $w-services-ci.yaml --ref main; done
  ```
  CI push image và ghi tag mới vào `gitops/dev-eks/`.

#warning[Vấn đề đã biết: ruleset `protect-main` từ chối lần push tag image mới của bot CI (lỗi GitHub `GH013`), nên bước 6 fail ở "Update GitOps and Push Back". Trong lúc chờ bản sửa ở roadmap, hãy tắt ruleset trong lúc bootstrap và bật lại ngay sau đó:
```bash
gh api -X PUT repos/khaipd18/online-boutique-gitops-pipeline/rulesets/24705847 -f enforcement=disabled
# ... chạy bước 6 và chờ mọi run kết thúc ...
gh api -X PUT repos/khaipd18/online-boutique-gitops-pipeline/rulesets/24705847 -f enforcement=active
```]

*Kiểm tra:*
```bash
kubectl -n argocd get applications            # tất cả Synced / Healthy
kubectl -n dev-eks get pods                   # tất cả Running, frontend có 2 replica
kubectl -n dev-eks get hpa,pdb                # HPA của frontend đọc được giá trị CPU
```
Mở địa chỉ shop và đặt thử một đơn; trang xác nhận đơn hàng phải hiện ra.

== RB-02 Gỡ môi trường

*Khi nào:* không còn cần môi trường. EKS không có free tier; control plane, node EC2, NAT Gateway và interface endpoint đều tính tiền theo giờ #link(facts.src.nat-pricing)[[AWS]].

+ Xóa các ứng dụng và load balancer trước. Load balancer do Kubernetes tạo nên không nằm trong Terraform state; nếu còn sót, `terraform destroy` sẽ fail ở bước xóa VPC.
  ```bash
  kubectl delete -f gitops/argocd/applicationset.yaml
  kubectl -n dev-eks delete svc frontend-external-dev --ignore-not-found
  ```
+ Gỡ hạ tầng (từ máy local, bằng credential admin):
  ```bash
  cd terraform && terraform destroy
  ```
+ Tùy chọn: xóa bucket state và bảng khóa nếu không dùng tài khoản này nữa.
+ Tùy chọn: xóa biến trên GitHub để CI lại bỏ qua các bước AWS: `gh variable delete AWS_ACCOUNT_ID`.

*Kiểm tra:* `aws eks list-clusters --region ap-southeast-1` không còn cluster, và EC2 console không còn load balancer hay NAT Gateway nào trong region.

== RB-03 Chuyển sang tài khoản AWS khác

+ Chạy RB-02 ở tài khoản cũ (hoặc chấp nhận để nó tiếp tục chạy).
+ Chạy RB-01 ở tài khoản mới. Không cần sửa code: Terraform lấy tài khoản từ credentials, còn CI lấy từ `AWS_ACCOUNT_ID`.
+ Địa chỉ ECR trong `gitops/dev-eks/values-*.yaml` vẫn trỏ về tài khoản cũ cho tới khi CI ghi đè ở bước 6 của RB-01.

= Quy trình thường ngày

== RB-04 Ra bản mới cho một service

+ Merge thay đổi trong `src/<service>/` vào `main`.
+ Workflow của ngôn ngữ đó lint, test, build, quét (Trivy) rồi push image tag bằng commit SHA, sau đó commit tag mới vào `gitops/dev-eks/values-<service>.yaml` kèm `[skip ci]`.
+ Argo CD phát hiện commit (mặc định kiểm tra mỗi 3 phút) và rollout image mới.

*Kiểm tra:*
```bash
gh run list --limit 5
kubectl -n argocd get application <service>-dev
kubectl -n dev-eks rollout status deploy/<service>-dev
kubectl -n dev-eks get deploy <service>-dev -o jsonpath='{..image}'; echo
```

== RB-05 Rollback một service

Mỗi tag image là một commit SHA và tag không đổi được, nên rollback nghĩa là cho file values trỏ lại tag trước đó.

+ Tìm commit đã đổi tag:
  ```bash
  git log --oneline -- gitops/dev-eks/values-<service>.yaml
  ```
+ Revert commit đó qua pull request (hoặc push thẳng bằng quyền admin khi khẩn cấp):
  ```bash
  git revert <commit-of-bad-tag>
  ```
+ Argo CD đưa service về image trước đó. Theo dõi bằng `kubectl -n dev-eks rollout status deploy/<service>-dev`.

#warning[Không dùng `kubectl set image` hay `kubectl rollout undo`: Argo CD self-heal sẽ khôi phục tag trong Git chỉ sau vài phút.]

== RB-06 Đổi cấu hình service

Biến môi trường, resource, probe, số replica, autoscaling và danh sách caller của NetworkPolicy đều nằm trong `gitops/dev-eks/values-<service>.yaml`.

+ Sửa file values trên một nhánh và render thử ở máy local:
  ```bash
  helm template <service>-dev helm-charts -f gitops/dev-eks/values-<service>.yaml -n dev-eks
  ```
+ Mở pull request; workflow Security Scan chạy Checkov trên manifest đã render.
+ Merge; Argo CD áp dụng thay đổi.

#tip[Khi một service bắt đầu gọi sang service khác, thêm tên release của bên gọi vào `networkPolicy.allowFrom` của bên được gọi, nếu không lời gọi sẽ bị timeout (xem IR-09).]

== RB-07 Thêm service mới

+ Thêm `gitops/dev-eks/values-<name>.yaml` (chép từ một service tương tự; giữ nguyên thiết lập bảo mật mặc định của chart).
+ Thêm `- name: <name>` vào list generator trong `gitops/argocd/applicationset.yaml`.
+ Thêm service vào `allowFrom` của những service mà nó gọi, và liệt kê các caller của nó trong `allowFrom` của chính nó.
+ Nếu có image mới: thêm tên repository ECR vào `repository_names` trong `terraform/variables.tf`, và thêm service vào workflow CI tương ứng (paths filter và danh sách khi chạy tay).
+ Apply thay đổi của ApplicationSet một lần: `kubectl apply -f gitops/argocd/applicationset.yaml` (bản thân ApplicationSet không do Argo CD quản lý).

== RB-08 Thay đổi hạ tầng

+ Sửa `terraform/` trên một nhánh và mở pull request.
+ *Checkov Scan* phải pass. *Terraform Plan* chạy bằng role read-only; đọc plan trong log của job.
+ Nhờ review pull request, rồi merge.
+ Job *Terraform Apply* chờ duyệt. Duyệt ở Actions → run tương ứng → Review deployments → `production` → Approve and deploy, hoặc:
  ```bash
  gh run list --workflow terraform.yaml --limit 1
  gh run view <run-id>          # hiện "waiting for review"
  ```
+ Xem log apply, rồi kiểm tra resource trên AWS.

#important[Chỉ duyệt khi đã đọc plan. Sau khi được duyệt, job apply chạy `terraform apply -auto-approve` với quyền `AdministratorAccess`.]

== RB-09 Scale

- *`frontend`:* HPA giữ 2–4 replica ở mức 70 % CPU. Đổi khoảng này trong `values-frontend.yaml` (`autoscaling.minReplicas` / `maxReplicas`).
- *Service khác:* đặt `replicaCount` hoặc bật `autoscaling.enabled` trong file values. PodDisruptionBudget tự được thêm từ 2 replica. Giữ `redis-cart` ở 1 (dữ liệu nằm trong `emptyDir`).
- *Node:* đổi `eks_node_group_scaling_config` (min/desired/max, hiện 1/2/3) theo RB-08. Chưa có cluster autoscaler: `desired_size` chính là số node.

== RB-10 Nâng phiên bản Kubernetes và add-on

Kubernetes 1.35 hết standard support ngày 27/03/2027 #link(facts.src.versions)[[AWS]]. Nâng từng minor version một, qua pull request (RB-08):

+ Đọc release note của EKS cho phiên bản đích và kiểm tra API bị deprecated trong manifest.
+ Tăng `eks_k8s_version` rồi apply: bước này chỉ nâng control plane.
+ Nâng managed node group. Module Terraform không đặt `version` cho node group, nên node giữ phiên bản cũ cho tới khi được cập nhật, và không được mới hơn control plane #link(facts.src.nodegroup-update)[[AWS]]:
  ```bash
  aws eks update-nodegroup-version --cluster-name khaipd18-eks-cluster \
    --nodegroup-name khaipd18-eks-cluster-node-group --kubernetes-version <version>
  ```
+ Tìm phiên bản add-on cho Kubernetes mới rồi tăng các biến `eks_*_version`:
  ```bash
  aws eks describe-addon-versions --addon-name vpc-cni --kubernetes-version <version> \
    --query 'addons[0].addonVersions[0:3].[addonVersion,compatibilities[0].defaultVersion]' --output text
  ```
  Làm tương tự cho `coredns`, `kube-proxy` và `metrics-server`.

*Kiểm tra:* `kubectl get nodes` cho thấy mọi node đã lên phiên bản mới; mọi Application của Argo CD đều Healthy; checkout trên shop vẫn chạy.

== RB-11 Chấp nhận hoặc sửa một finding Checkov

+ Ưu tiên sửa Terraform. Nếu finding chấp nhận được, ghi rõ lý do (comment ngay cạnh resource).
+ Tạo lại baseline trong một pull request để được review:
  ```bash
  checkov --config-file .checkov.yaml -d terraform --framework terraform --create-baseline
  ```

== RB-12 Xử lý lỗ hổng trong image

+ Mở tab *Security* của GitHub → Code scanning, lọc theo tool *Trivy* và image (`trivy-<service>`). Mỗi run cũng ghi số lỗ hổng của từng image trong job summary.
+ Finding đến từ base image và dependency trong `src/`, phần repository này không sửa. Nâng cấp chúng là việc thay đổi code của chủ ứng dụng; sau đó repository này chuyển gate sang blocking bằng cách đặt `blocking: 'true'` ở bước Trivy.
+ SBOM (CycloneDX) của từng image được lưu thành artifact của run trong 30 ngày (`sbom-<service>`).

== RB-13 Kiểm soát chi phí

#table(
  columns: (34%, 1fr),
  [Hạng mục tính phí], [Ghi chú],
  [EKS control plane], [Tính theo giờ khi cluster còn tồn tại],
  [Node EC2], [Mặc định 2 × `t3.medium` on-demand],
  [NAT Gateway], [Theo giờ và theo GB xử lý #link(facts.src.nat-pricing)[[AWS]]],
  [Interface endpoint], [3 endpoint × 2 AZ, theo giờ và theo GB],
  [Classic Load Balancer], [Theo giờ và theo GB],
  [CloudWatch Logs], [5 loại control plane log; đặt thời gian lưu nếu để chạy lâu],
  [ECR, S3, DynamoDB], [Nhỏ: dung lượng lưu trữ và số request],
)

Kiểm tra chi phí thực tế bằng AWS Cost Explorer của tài khoản. Gỡ môi trường (RB-02) khi không dùng.

= Monitoring

== Kiểm tra hằng ngày

```bash
kubectl -n argocd get applications                 # Synced / Healthy
kubectl -n dev-eks get pods                        # Running, số lần restart không tăng
kubectl -n dev-eks get hpa                         # CPU của frontend dưới mục tiêu
kubectl get nodes                                  # Ready
gh run list --limit 10                             # kết quả CI gần đây
```

== Cần theo dõi gì trên Grafana

kube-prometheus-stack có sẵn dashboard cho cluster, node, namespace và workload. Theo dõi:

- Số lần pod restart và container bị `OOMKilled` trong #raw(facts.namespace) (dashboard *Kubernetes / Compute Resources / Namespace (Pods)*).
- CPU và memory của từng pod so với request và limit ở Phụ lục A.
- CPU và memory của node: với 2 node `t3.medium`, cluster không còn nhiều dư địa.
- Số replica của `frontend` (hoạt động của HPA).

Hiện chưa có alert rule cho ứng dụng; Alertmanager chỉ có các rule mặc định. Alert theo SLO nằm trong roadmap.

== Log

- Log của pod: `kubectl -n dev-eks logs deploy/<service>-dev --tail 100` (thêm `--previous` sau khi crash).
- Control plane log (api, audit, authenticator, controllerManager, scheduler): log group `/aws/eks/khaipd18-eks-cluster/cluster` trên CloudWatch Logs.
- Log CI: `gh run view <run-id> --log-failed`.

= Xử lý sự cố

== IR-01 CI fail ở bước "Configure AWS credentials"

#playbook(
  symptom: [`Could not assume role with OIDC: Not authorized to perform sts:AssumeRoleWithWebIdentity` hoặc `The web identity token provided could not be validated`.],
  cause: [`AWS_ACCOUNT_ID` trỏ tới tài khoản sai hoặc đã bỏ; role hay OIDC provider chưa tồn tại ở đó; claim `sub` của token không khớp trust policy (ví dụ job apply không dùng environment `production`).],
  diagnose: [`gh variable list`; trong tài khoản: `aws iam get-role --role-name github-actions-ecr-oidc-role --query Role.AssumeRolePolicyDocument`; so các giá trị `sub` được phép với job (nhánh `main`, `pull_request` hay `environment:production`).],
  fix: [Sửa biến, hoặc chạy bước 4 của RB-01 để tạo role. Muốn tạm dừng hẳn các bước AWS, xóa biến đi: CI khi đó chỉ lint, test, build và scan.],
)

== IR-02 Terraform state bị khóa không nhả

#playbook(
  symptom: [`Error acquiring the state lock` kèm một lock ID, dù không có apply nào đang chạy.],
  cause: [Một run trước bị hủy hoặc crash khi đang giữ khóa DynamoDB.],
  diagnose: [Chắc chắn không có job Terraform nào đang chạy: `gh run list --workflow terraform.yaml`. Ghi lại lock ID và ai đang giữ khóa từ thông báo lỗi.],
  fix: [Từ máy local với credential admin: `cd terraform && terraform force-unlock <lock-id>`. Tuyệt đối không mở khóa khi có apply khác đang chạy: hai lần apply song song có thể làm hỏng state. Bucket state có versioning nên state hỏng có thể khôi phục từ phiên bản object trước đó.],
)

== IR-03 Terraform Apply không chạy

#playbook(
  symptom: [Run hiện *Waiting* ở job Terraform Apply.],
  cause: [Environment `production` cần người duyệt.],
  diagnose: [`gh run view <run-id>`; job đang chờ review deployment.],
  fix: [Đọc plan trong pull request, rồi duyệt ở trang của run (Review deployments). Từ chối nếu plan khác với những gì đã review.],
)

== IR-04 GitOps write-back bị từ chối

#playbook(
  symptom: [Bước "Update GitOps and Push Back" fail với `GH013: Repository rule violations found` / `Changes must be made through a pull request`. Image đã có trên ECR nhưng cluster vẫn chạy tag cũ.],
  cause: [Ruleset `protect-main` bắt buộc qua pull request, và repository cá nhân không đưa được app GitHub Actions vào danh sách bypass.],
  diagnose: [`gh run view <run-id> --log-failed`.],
  fix: [Trước mắt: tự cập nhật tag trong `gitops/dev-eks/values-<service>.yaml` (qua pull request hoặc push bằng quyền admin), lấy SHA từ run; hoặc tắt ruleset trong lúc CI chạy (cảnh báo ở RB-01). Sửa lâu dài (roadmap): deploy key trong danh sách bypass, hoặc cho bot mở pull request.],
)

== IR-05 Application của Argo CD bị OutOfSync hoặc Degraded

#playbook(
  symptom: [`kubectl -n argocd get applications` hiện `OutOfSync`, `Degraded` hoặc `Progressing` trong thời gian dài.],
  cause: [Values sai (lỗi render), pod không bao giờ ready, resource bị sửa tay, hoặc một field do controller khác quản lý.],
  diagnose: [`kubectl -n argocd describe application <service>-dev` (conditions và kết quả sync); `kubectl -n dev-eks get events --sort-by=.lastTimestamp | tail -20`; render thử ở local bằng `helm template`.],
  fix: [Sửa values trong Git. Nếu sync bị kẹt, refresh trên giao diện Argo CD (Refresh → Hard refresh) hoặc `kubectl -n argocd annotate application <service>-dev argocd.argoproj.io/refresh=hard --overwrite`.],
)

== IR-06 Pod bị ImagePullBackOff

#playbook(
  symptom: [Pod ở trạng thái `ImagePullBackOff` hoặc `ErrImagePull`.],
  cause: [Tag không có trên ECR (CI chưa push, hoặc values vẫn trỏ tới tài khoản khác); node không tới được ECR.],
  diagnose: [`kubectl -n dev-eks describe pod <pod>` (phần Events ghi image và lỗi); `aws ecr describe-images --repository-name <service> --image-ids imageTag=<tag>`; kiểm tra account trong địa chỉ image có đúng tài khoản hiện tại.],
  fix: [Chạy workflow CI của service để build và push tag, hoặc rollback về tag đã có (RB-05). Nếu không tới được ECR, kiểm tra endpoint `ecr.api`/`ecr.dkr` và route tới S3 gateway endpoint trong route table private.],
)

== IR-07 Pod bị CrashLoopBackOff hoặc OOMKilled

#playbook(
  symptom: [Số lần restart tăng dần; `kubectl get pods` hiện `CrashLoopBackOff`; `describe` hiện `Last State: Terminated, Reason: OOMKilled`.],
  cause: [Memory limit quá thấp, biến môi trường sai, hoặc một service phụ thuộc chưa sẵn sàng lúc khởi động.],
  diagnose: [`kubectl -n dev-eks logs <pod> --previous`; `kubectl -n dev-eks describe pod <pod>`; so mức dùng trên Grafana với limit.],
  fix: [Sửa values (RB-06) hoặc rollback (RB-05). Ví dụ đã gặp: `GOMEMLIMIT: "230Mi"` làm `frontend` crash ngay khi khởi động vì Go chỉ nhận đơn vị kiểu `MiB`; bản sửa là `230MiB` (commit `feb47a7`).],
)

== IR-08 Pod bị Pod Security Admission từ chối

#playbook(
  symptom: [Event của ReplicaSet hiện `Error creating: pods ... is forbidden: violates PodSecurity "restricted:latest"`.],
  cause: [Values ghi đè thiết lập an toàn mặc định của chart (chạy bằng root, cho leo thang đặc quyền, thiếu seccomp profile, thêm capability).],
  diagnose: [`kubectl -n dev-eks describe rs -l app=<service>-dev`; thông báo liệt kê từng vi phạm.],
  fix: [Bỏ phần ghi đè trong file values. Không nới label của namespace; nếu workload thật sự cần, ghi lại ngoại lệ trước.],
)

== IR-09 Lời gọi giữa các service bị timeout

#playbook(
  symptom: [Một trang hoặc bước checkout lỗi gRPC `DeadlineExceeded` / `Unavailable` sau một thay đổi; pod đích vẫn khỏe.],
  cause: [Bên gọi không có trong `networkPolicy.allowFrom` của bên được gọi, hoặc port đã đổi.],
  diagnose: [`kubectl -n dev-eks get networkpolicy <target>-dev -o yaml`; thử gọi từ một pod mang label của bên gọi so với một pod khác.],
  fix: [Thêm tên release của bên gọi vào `allowFrom` của bên được gọi (RB-06).],
)

== IR-10 Không vào được shop từ internet

#playbook(
  symptom: [Địa chỉ shop bị timeout, hoặc `EXTERNAL-IP` cứ ở `<pending>`.],
  cause: [Load balancer đang được tạo (DNS có thể mất vài phút); không có pod `frontend` nào khỏe; Service đã bị xóa.],
  diagnose: [`kubectl -n dev-eks describe svc frontend-external-dev` (events); `kubectl -n dev-eks get pods -l app=frontend-dev`; xem tình trạng instance trong EC2 console, mục Load Balancers.],
  fix: [Chờ tạo xong; sửa `frontend` (IR-06/IR-07); để Argo CD tạo lại Service (sync `frontend-external-dev`).],
)

== IR-11 Pod bị Pending hoặc node NotReady

#playbook(
  symptom: [Pod nằm ở `Pending` với `Insufficient cpu`/`memory`, hoặc một node ở trạng thái `NotReady`.],
  cause: [Tổng request vượt khả năng của 2 node `t3.medium` (ví dụ sau khi scale); một node gặp lỗi.],
  diagnose: [`kubectl describe pod <pod>` (thông báo của scheduler); `kubectl describe node <node>` (resource đã cấp, conditions); `kubectl top nodes`.],
  fix: [Giảm replica hoặc request, hoặc tăng kích thước node group (RB-09). Node lỗi trong managed node group sẽ được EKS thay; nếu không, cordon, drain rồi terminate instance đó.],
)

== IR-12 HPA hiện metrics `<unknown>`

#playbook(
  symptom: [`kubectl -n dev-eks get hpa` hiện `cpu: <unknown>/70%`; `frontend` không scale.],
  cause: [Metrics Server không có hoặc chưa sẵn sàng, hoặc pod không đặt CPU request.],
  diagnose: [`kubectl -n kube-system get deploy metrics-server`; `kubectl top pods -n dev-eks`; `aws eks describe-addon --cluster-name khaipd18-eks-cluster --addon-name metrics-server`.],
  fix: [Apply lại Terraform để add-on `metrics-server` được cài và chạy ổn định; giữ `resources.requests.cpu` trong values.],
)

== IR-13 Không drain được node

#playbook(
  symptom: [`kubectl drain` hoặc lần cập nhật node group lặp mãi với `Cannot evict pod as it would violate the pod's disruption budget`.],
  cause: [Drain sẽ khiến `frontend` không còn pod nào chạy, điều mà PodDisruptionBudget không cho phép. Đây là cơ chế bảo vệ có chủ đích.],
  diagnose: [`kubectl -n dev-eks get pdb`; xem pod `frontend` đang chạy ở đâu và node khác còn chỗ không.],
  fix: [Tạo chỗ trên node khác (tăng node group) để pod bị evict được xếp lại, rồi thử lại. Không xóa PDB.],
)

== IR-14 Giỏ hàng bị trống

#playbook(
  symptom: [Người dùng báo giỏ hàng tự nhiên trống.],
  cause: [`redis-cart` khởi động lại; dữ liệu nằm trong volume `emptyDir` nên mất khi khởi động lại.],
  diagnose: [`kubectl -n dev-eks get pod -l app=redis-cart-dev` (tuổi pod, số lần restart).],
  fix: [Đây là hành vi đã biết của bản demo. Cần kho lưu bền vững (ElastiCache hoặc PersistentVolume) trước khi dùng thật.],
)

= Khôi phục sau thảm họa

#table(
  columns: (28%, 1fr),
  [Mất gì], [Khôi phục thế nào],
  [Toàn bộ cluster hoặc tài khoản], [RB-01 dựng lại mọi thứ từ Git: hạ tầng (Terraform), ứng dụng (Argo CD), image (CI). Khoảng 45 phút.],
  [Terraform state], [Bucket S3 có versioning: khôi phục phiên bản object trước đó của #raw(facts.state-key).],
  [Một lần deploy lỗi], [RB-05 (revert commit đổi tag).],
  [Dữ liệu giỏ hàng], [Không khôi phục được (không lưu bền vững).],
  [Cấu hình Grafana và dữ liệu lịch sử của Prometheus], [Không được backup; dashboard có lại cùng chart, dữ liệu lịch sử thì không.],
)

#heading(numbering: none)[Phụ lục A. Service và port]

#table(
  columns: (auto, auto, auto, 1fr, auto, auto),
  [Service], [Ngôn ngữ], [Port], [Nhận lời gọi từ], [CPU req/limit], [Memory req/limit],
  ..facts.services.flatten(),
)

`frontend-external-dev` là Service kiểu LoadBalancer (`80 → 8080`) trỏ vào các pod `frontend-dev`.

#heading(numbering: none)[Phụ lục B. Lệnh thường dùng]

```bash
# Trạng thái tổng thể
kubectl -n argocd get applications
kubectl -n dev-eks get deploy,pods,svc,hpa,pdb,networkpolicy

# Một service
kubectl -n dev-eks describe pod -l app=<service>-dev
kubectl -n dev-eks logs deploy/<service>-dev --tail 100 [--previous]
kubectl -n dev-eks rollout status deploy/<service>-dev

# CI
gh run list --limit 10
gh run view <run-id> --log-failed
gh workflow run <language>-services-ci.yaml --ref main

# Render một release ở local
helm template <service>-dev helm-charts -f gitops/dev-eks/values-<service>.yaml -n dev-eks

# Terraform (máy local, chỉ khi khẩn cấp)
cd terraform && terraform init && terraform plan
terraform force-unlock <lock-id>
```

#heading(numbering: none)[Phụ lục C. Phiên bản]

#table(
  columns: (32%, 28%, 1fr),
  [Thành phần], [Phiên bản], [Khai báo ở],
  ..facts.versions.flatten(),
)
