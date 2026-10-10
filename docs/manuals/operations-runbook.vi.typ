#import "lib/template.typ": manual, callout, palette, shot
#import "lib/facts.typ" as facts

#let note = callout.with("note", lang: "vi")
#let warning = callout.with("warning", lang: "vi")
#let important = callout.with("important", lang: "vi")
#let tip = callout.with("tip", lang: "vi")

#set heading(supplement: [Mục])
#set figure(supplement: it => if it.func() == table { [Bảng] } else { [Hình] })

#show: manual.with(
  title: "Sổ tay vận hành",
  subtitle: "Cách chạy, kiểm tra, thay đổi và tắt hệ thống",
  doc-id: "OBE-RUN-001-VI",
  version: "2.0",
  date: facts.doc-date,
  status: "Đã duyệt cho môi trường dev",
  owner: "khaipd18 (DevOps / Cloud)",
  audience: "Kỹ sư triển khai hoặc vận hành hệ thống",
  classification: "Nội bộ",
  repository: facts.repo-url,
  lang: "vi",
  revisions: (
    ("1.0", "2026-10-09", "Phát hành lần đầu.", "khaipd18"),
    ("1.1", "2026-10-10", "Chạy thật trên tài khoản mới; Terraform quản lý log group của control plane.", "khaipd18"),
    ("1.2", "2026-10-10", "Thêm ảnh chụp từ lần triển khai đầy đủ trên EKS; thêm IR-15.", "khaipd18"),
    ("2.0", facts.doc-date, "Viết lại cho ngắn gọn: các việc chính theo từng bước đơn giản, mọi sự cố gộp vào một bảng, phần nâng cao chuyển xuống phụ lục.", "khaipd18"),
  ),
  related: (
    [OBE-TDD-001-VI Tài liệu thiết kế kỹ thuật: vì sao hệ thống được xây như vậy],
    [Bản tiếng Anh: `docs/manuals/operations-runbook.en.pdf` (OBE-RUN-001)],
    [README.vi.md: tóm tắt dự án và cách chạy thử ở máy local với kind],
  ),
)

= Bắt đầu từ đây

== Cái gì chạy ở đâu

#table(
  columns: (30%, 1fr),
  [Thành phần], [Nằm ở đâu],
  [Hạ tầng (VPC, EKS, ECR, IAM)], [AWS #raw(facts.region), do Terraform tạo từ thư mục `terraform/`],
  [Cluster Kubernetes], [#raw(facts.cluster), 3 node `t3.medium`],
  [Shop (12 service)], [Namespace #raw(facts.namespace), Argo CD deploy từ `gitops/dev-eks/`],
  [Argo CD], [Namespace `argocd`, chạy bên trong cluster],
  [Monitoring (Prometheus, Grafana)], [Namespace `monitoring`],
  [CI/CD], [GitHub Actions trong repository],
)

== Ba quy tắc

+ *Mọi thay đổi đi qua Git.* Argo CD luôn đưa cluster về đúng như trong Git, nên sửa tay bằng `kubectl` sẽ bị hoàn lại sau vài phút.
+ *Thay đổi hạ tầng phải qua pull request.* Bước Terraform apply sẽ chờ bạn bấm duyệt trên GitHub.
+ *Dùng xong thì tắt môi trường.* Chạy tốn khoảng 0,40 USD mỗi giờ, chưa tính load balancer (Phụ lục C).

== Công cụ cần có

AWS CLI v2, Terraform 1.14 trở lên, `kubectl`, Helm, GitHub CLI (`gh`). Đăng nhập AWS bằng profile của tài khoản rồi kiểm tra:

```bash
aws sts get-caller-identity          # xem đang dùng tài khoản nào
aws eks update-kubeconfig --region ap-southeast-1 --name khaipd18-eks-cluster
kubectl get nodes                    # 3 node, đều Ready
```

#note[Chỉ danh tính đã tạo cluster mới có quyền admin. Role dùng trên AWS console được Terraform tự cấp quyền chỉ đọc, nên EKS console xem được pod và node.]

= Các việc chính

== Dựng môi trường

*Thời gian:* khoảng 45 phút. *Bắt đầu tính tiền từ bước 3.*

+ *Báo cho GitHub biết dùng tài khoản AWS nào:*
  ```bash
  gh variable set AWS_ACCOUNT_ID --body <account-id>
  ```
+ *Tạo chỗ lưu state của Terraform* (mỗi tài khoản chỉ làm một lần):
  ```bash
  aws s3api create-bucket --bucket <state-bucket> --region ap-southeast-1 \
    --create-bucket-configuration LocationConstraint=ap-southeast-1
  aws s3api put-bucket-versioning --bucket <state-bucket> \
    --versioning-configuration Status=Enabled
  aws dynamodb create-table --table-name <lock-table> --region ap-southeast-1 \
    --attribute-definitions AttributeName=LockID,AttributeType=S \
    --key-schema AttributeName=LockID,KeyType=HASH --billing-mode PAY_PER_REQUEST
  ```
  Tên phải khớp với `terraform/backend.tf`.
+ *Tạo hạ tầng* (khoảng 17 phút):
  ```bash
  cd terraform
  terraform init
  terraform plan -out tfplan     # đọc plan: 74 resource sẽ được tạo
  terraform apply tfplan
  ```
+ *Cài Argo CD và chỉ cho nó những gì cần deploy:*
  ```bash
  aws eks update-kubeconfig --region ap-southeast-1 --name khaipd18-eks-cluster
  kubectl create namespace argocd
  kubectl apply -n argocd --server-side -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
  kubectl apply -f gitops/argocd/namespaces.yaml
  kubectl apply -f gitops/argocd/applicationset.yaml
  kubectl apply -f gitops/argocd/monitoring.yaml --server-side
  ```
+ *Build image.* Quy tắc bảo vệ nhánh `main` chặn bot CI, nên tạm tắt nó một lúc:
  ```bash
  gh api -X PUT repos/khaipd18/online-boutique-gitops-pipeline/rulesets/24705847 -f enforcement=disabled
  for w in go dotnet java node py; do gh workflow run $w-services-ci.yaml --ref main; done
  # chờ 5 run xanh hết: gh run list --limit 5
  gh api -X PUT repos/khaipd18/online-boutique-gitops-pipeline/rulesets/24705847 -f enforcement=active
  ```
+ *Kiểm tra:* làm theo mục tiếp theo. Mọi thứ phải giống ảnh trong mục đó.

== Kiểm tra hệ thống chạy tốt

Chạy 4 lệnh sau:

```bash
kubectl get nodes                       # 3 node, đều Ready
kubectl -n argocd get applications      # 14 app, đều Synced và Healthy
kubectl -n dev-eks get pods             # đều Running, số lần restart không tăng
kubectl -n dev-eks get hpa              # CPU của frontend dưới 70%
```

#shot("terminal-daily.png", [Một cluster khỏe trông như thế này])

Mở shop: lấy địa chỉ bằng `kubectl -n dev-eks get svc frontend-external-dev`, mở hostname ở cột `EXTERNAL-IP` trên trình duyệt rồi đặt thử một đơn.

#shot("shop-order-complete.png", [Đặt thử đơn hàng thành công: cả shop hoạt động], width: 75%)

*Mở các giao diện web* (mỗi lệnh chạy liên tục; mở địa chỉ trên trình duyệt):

#table(
  columns: (18%, 1fr, 22%),
  [Giao diện], [Lệnh], [Địa chỉ],
  [Argo CD], [`kubectl -n argocd port-forward svc/argocd-server 8080:443`], [https://localhost:8080],
  [Grafana], [`kubectl -n monitoring port-forward svc/kube-prometheus-stack-grafana 3000:80`], [http://localhost:3000],
)

User là `admin`. Lấy mật khẩu:
```bash
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d; echo
kubectl -n monitoring get secret kube-prometheus-stack-grafana -o jsonpath='{.data.admin-password}' | base64 -d; echo
```

#shot("argocd-applications.png", [Argo CD: mọi app đều Synced và Healthy])
#shot("grafana-namespace-pods.png", [Grafana, dashboard "Kubernetes / Compute Resources / Namespace (Pods)": CPU và memory của từng pod])
#shot("console-eks-nodes.png", [AWS console, EKS → Compute: ba node Ready])

== Ra bản mới cho một service

+ Merge thay đổi trong `src/<service>/` vào `main`.
+ GitHub Actions test, build và quét image, đẩy lên ECR rồi ghi tag mới vào `gitops/dev-eks/values-<service>.yaml`.
+ Khoảng 3 phút sau Argo CD thấy tag mới và cập nhật pod.

Kiểm tra: `kubectl -n dev-eks rollout status deploy/<service>-dev`

#shot("github-ci-run.png", [Một run CI thành công trên GitHub Actions])

== Rollback một service

Mỗi tag image ứng với một commit, nên quay lại bản cũ chỉ là khôi phục tag trước đó trong Git:

```bash
git log --oneline -- gitops/dev-eks/values-<service>.yaml   # tìm commit đổi sang tag lỗi
git revert <commit>                                          # rồi push hoặc mở PR
```

#warning[Không dùng `kubectl set image` hay `kubectl rollout undo`. Argo CD sẽ đưa bản lỗi quay lại.]

== Đổi cấu hình hoặc scale một service

Mọi cấu hình của một service nằm trong `gitops/dev-eks/values-<service>.yaml`: biến môi trường, CPU và memory, số replica, autoscaling, và những service nào được gọi tới nó (`networkPolicy.allowFrom`).

+ Sửa file trên một nhánh.
+ Xem trước kết quả: `helm template <service>-dev helm-charts -f gitops/dev-eks/values-<service>.yaml`
+ Mở pull request rồi merge. Argo CD tự áp dụng.

#tip[Khi một service bắt đầu gọi sang service khác, thêm nó vào `allowFrom` của service được gọi, nếu không lời gọi sẽ bị chặn.]

Muốn đổi số *node*, sửa `eks_node_group_scaling_config` trong `terraform/variables.tf` rồi làm theo mục tiếp theo.

#shot("argocd-frontend-tree.png", [Argo CD hiển thị mọi thứ thuộc một service: Deployment, pod, HPA, NetworkPolicy, PodDisruptionBudget])

== Thay đổi hạ tầng

+ Sửa `terraform/` trên một nhánh rồi mở pull request.
+ GitHub chạy Checkov (kiểm tra bảo mật) và `terraform plan`. Đọc plan trong log của job.
+ Merge pull request.
+ Job *Terraform Apply* sẽ chờ. Trên GitHub: *Actions* → run đó → *Review deployments* → *production* → *Approve*.

#important[Chỉ duyệt khi đã đọc plan. Bước apply chạy với quyền admin đầy đủ.]

== Tắt môi trường

+ Xóa các app và load balancer trước (còn load balancer thì Terraform không xóa được VPC):
  ```bash
  kubectl delete -f gitops/argocd/applicationset.yaml
  kubectl -n dev-eks delete svc frontend-external-dev --ignore-not-found
  ```
+ Xóa hạ tầng (khoảng 10 phút):
  ```bash
  cd terraform && terraform destroy
  ```
+ Báo CI rằng không còn tài khoản AWS: `gh variable delete AWS_ACCOUNT_ID`

Kiểm tra: `aws eks list-clusters --region ap-southeast-1` trả về danh sách rỗng. Bucket state và bảng khóa được giữ lại, gần như không tốn tiền.

= Khi có sự cố

Tìm dấu hiệu trong bảng rồi làm theo cách sửa. Lệnh ở cột giữa thường cho biết nguyên nhân.

#table(
  columns: (26%, 1fr, 1fr),
  [Dấu hiệu], [Nguyên nhân thường gặp / cách xem], [Cách sửa],
  [CI lỗi ở bước "Configure AWS credentials"], [Sai `AWS_ACCOUNT_ID`, hoặc chưa có IAM role. `gh variable list`], [Sửa biến, hoặc tạo role bằng lần `terraform apply` đầu tiên],
  [CI lỗi ở bước "Update GitOps", báo `GH013`], [Quy tắc của `main` chặn bot], [Tạm tắt quy tắc trong lúc CI chạy (Dựng môi trường, bước 5)],
  [Terraform báo `Error acquiring the state lock`], [Một lần chạy trước bị dừng giữa chừng. Chắc chắn không có gì đang chạy: `gh run list`], [`terraform force-unlock <lock-id>`],
  [Job Terraform Apply đứng ở *Waiting*], [Đang chờ bạn duyệt], [Duyệt trên GitHub (Thay đổi hạ tầng)],
  [App trên Argo CD *OutOfSync* hoặc *Degraded*], [Values sai hoặc pod không khởi động được. `kubectl -n argocd describe application <app>`], [Sửa values trong Git],
  [Pod bị `ImagePullBackOff`], [Tag image không có trên ECR. `kubectl -n dev-eks describe pod <pod>`], [Chạy CI của service, hoặc rollback],
  [Pod bị `CrashLoopBackOff` / `OOMKilled`], [Cấu hình sai hoặc thiếu memory. `kubectl -n dev-eks logs <pod> --previous`], [Sửa values hoặc rollback],
  [Pod báo `forbidden: violates PodSecurity`], [Values đã bỏ các thiết lập bảo mật an toàn], [Bỏ phần ghi đè đó trong file values],
  [Lời gọi giữa các service bị timeout], [Bên gọi chưa có trong `allowFrom`. `kubectl -n dev-eks get networkpolicy`], [Thêm bên gọi vào `allowFrom`],
  [Không mở được địa chỉ shop], [Load balancer chưa sẵn sàng, hoặc `frontend` đang lỗi. `kubectl -n dev-eks get pods`], [Chờ vài phút; sửa `frontend`],
  [Pod nằm mãi ở `Pending`], [Node không còn chỗ. `kubectl describe pod <pod>`], [Giảm replica hoặc thêm node],
  [HPA hiện `<unknown>`], [Metrics Server chưa sẵn sàng. `kubectl top pods -n dev-eks`], [Apply lại Terraform (nó cài Metrics Server)],
  [`kubectl drain` không bao giờ xong], [PodDisruptionBudget giữ lại một pod `frontend` (có chủ đích)], [Thêm node để pod chuyển sang, rồi thử lại],
  [Giỏ hàng bị trống], [`redis-cart` khởi động lại; giỏ hàng không lưu xuống đĩa], [Bình thường với bản demo này],
  [EKS console báo "Data unavailable"], [Role dùng trên console chưa có quyền trong cluster], [Apply lại Terraform (nó cấp quyền đọc cho role console)],
)

#shot("terminal-security.png", [Bảo mật hoạt động đúng thiết kế: pod thiếu thiết lập bảo mật bị từ chối; pod không được phép thì không gọi được `paymentservice` hay `redis-cart`])

#important[Nếu người dùng bị ảnh hưởng (shop sập, không checkout được), rollback trước rồi mới điều tra. Ghi lại sự việc vào một GitHub issue.]

#heading(numbering: none)[Phụ lục]

#heading(level: 2, numbering: none)[A. Nâng phiên bản Kubernetes]

EKS hỗ trợ Kubernetes 1.35 tới ngày 27/03/2027 #link(facts.src.versions)[[AWS]]. Mỗi lần chỉ nâng một phiên bản:

+ Xem *EKS console → Upgrade insights*: mọi mục phải *Passing*.
+ Đổi `eks_k8s_version` trong Terraform rồi apply. Bước này nâng control plane.
+ Nâng node; Terraform không tự làm việc này #link(facts.src.nodegroup-update)[[AWS]]:
  ```bash
  aws eks update-nodegroup-version --cluster-name khaipd18-eks-cluster \
    --nodegroup-name khaipd18-eks-cluster-node-group --kubernetes-version <version>
  ```
+ Nâng phiên bản các add-on (các biến `eks_*_version`). Xem phiên bản bằng
  `aws eks describe-addon-versions --addon-name <tên> --kubernetes-version <version>`.

#shot("console-eks-upgrade-insights.png", [EKS upgrade insights: mọi mục đều Passing])

#heading(level: 2, numbering: none)[B. Lỗ hổng bảo mật]

- *Checkov (Terraform):* sửa code nếu được. Nếu chấp nhận một finding, ghi rõ lý do rồi cập nhật baseline trong một pull request:
  `checkov --config-file .checkov.yaml -d terraform --framework terraform --create-baseline`
- *Trivy (image):* xem trên GitHub → *Security* → *Code scanning*. Các lỗ hổng đến từ code ứng dụng trong `src/`, phần repository này không sửa, nên chúng được báo cáo nhưng không chặn CI.

#shot("github-code-scanning.png", [GitHub code scanning: finding của Trivy theo từng image])

#heading(level: 2, numbering: none)[C. Chi phí]

Khoảng *0,40 USD mỗi giờ* khi môi trường chạy, chưa tính load balancer và các khoản nhỏ (giá on-demand ở #raw(facts.region), lấy từ AWS Price List API): EKS control plane 0,10; ba node `t3.medium` 0,16; sáu ENI của interface endpoint 0,08; NAT Gateway 0,06. Xem chi phí thật trên AWS Cost Explorer. Không dùng thì tắt môi trường.

#heading(level: 2, numbering: none)[D. Khôi phục]

#table(
  columns: (30%, 1fr),
  [Mất gì], [Lấy lại thế nào],
  [Toàn bộ cluster hoặc tài khoản], [Dựng lại môi trường: mọi thứ được tạo lại từ Git trong khoảng 45 phút],
  [Terraform state], [Bucket state giữ các phiên bản cũ: khôi phục phiên bản trước của #raw(facts.state-key)],
  [Một lần deploy lỗi], [Rollback service],
  [Giỏ hàng, dữ liệu lịch sử Grafana], [Không được lưu; sẽ mất],
)

#heading(level: 2, numbering: none)[E. Service và port]

#table(
  columns: (auto, auto, auto, 1fr, auto, auto),
  [Service], [Ngôn ngữ], [Port], [Nhận lời gọi từ], [CPU req/limit], [Memory req/limit],
  ..facts.services.flatten(),
)

#heading(level: 2, numbering: none)[F. Phiên bản]

#table(
  columns: (32%, 28%, 1fr),
  [Thành phần], [Phiên bản], [Khai báo ở],
  ..facts.versions.flatten(),
)
