#import "lib/template.typ": manual, callout, palette, shot
#import "lib/facts.typ" as facts

#let note = callout.with("note", lang: "vi")
#let warning = callout.with("warning", lang: "vi")
#let important = callout.with("important", lang: "vi")

#set heading(supplement: [Mục])
#set figure(supplement: it => if it.func() == table { [Bảng] } else { [Hình] })

#show: manual.with(
  title: "Tài liệu thiết kế kỹ thuật",
  subtitle: "Thiết kế nền tảng, pipeline triển khai và bảo mật",
  doc-id: "OBE-TDD-001-VI",
  version: "1.2",
  date: facts.doc-date,
  status: "Đã duyệt cho môi trường dev",
  owner: "khaipd18 (DevOps / Cloud)",
  audience: "Kỹ sư Cloud và DevOps, người review bảo mật, người bảo trì",
  classification: "Nội bộ",
  repository: facts.repo-url,
  lang: "vi",
  revisions: (
    ("1.0", "2026-10-09", "Phát hành lần đầu: hạ tầng, nền tảng Kubernetes, CI/CD, bảo mật và các quyết định thiết kế.", "khaipd18"),
    ("1.1", "2026-10-10", "Chạy thật trên tài khoản mới: đổi tên bucket state, Terraform quản lý log group của control plane (74 resource), đã kiểm chứng apply và destroy.", "khaipd18"),
    ("1.2", facts.doc-date, "Triển khai đầy đủ trên EKS kèm ảnh chụp; mặc định 3 node; quyền vào cluster qua EKS access entry; quyết định D11 về Argo CD.", "khaipd18"),
  ),
  related: (
    [OBE-RUN-001-VI Sổ tay vận hành (`docs/manuals/operations-runbook.vi.pdf`)],
    [Bản tiếng Anh của tài liệu này: `docs/manuals/technical-design.en.pdf` (OBE-TDD-001)],
    [README.vi.md: tóm tắt dự án, kết quả kiểm chứng và hướng dẫn chạy thử local],
    [`docs/infrastructure/`: sơ đồ HLD/LLD sửa được (`.drawio`) và YAML spec tương ứng],
  ),
)

= Giới thiệu

== Mục đích

Tài liệu này mô tả cách nền tảng Online Boutique được xây dựng trên AWS (hạ tầng, nền tảng Kubernetes, pipeline triển khai, các lớp bảo mật) và lý do đằng sau từng lựa chọn thiết kế. Đây là tài liệu tham chiếu cho bất kỳ ai thay đổi nền tảng. Các quy trình hằng ngày (triển khai, ra bản mới, xử lý sự cố) nằm trong Sổ tay vận hành (OBE-RUN-001-VI).

== Phạm vi

Trong phạm vi:
- Hạ tầng AWS, không gắn với một tài khoản cụ thể, ở region #raw(facts.region): VPC, EKS, ECR, VPC endpoint, IAM role cho GitHub Actions, backend lưu Terraform state.
- Nền tảng Kubernetes trong namespace #raw(facts.namespace): Helm chart, cấu hình Argo CD, Pod Security, NetworkPolicy, autoscaling, bộ monitoring.
- CI/CD: các workflow GitHub Actions, quality gate và security gate, GitOps write-back, pipeline Terraform, các kiểm soát trên repository.

Ngoài phạm vi:
- Mã nguồn ứng dụng trong `src/` và `protos/`. Đây là Online Boutique của Google (Apache License 2.0) và được giữ nguyên; những phát hiện chỉ sửa được bằng cách đổi mã nguồn này thì được báo cáo, không sửa.
- Môi trường staging và production. Hiện chỉ có một môi trường (`dev`); @roadmap liệt kê những gì môi trường production cần thêm.

== Hiện trạng

Nền tảng đã chạy trên Amazon EKS vào tháng 5/2026 (Terraform dựng hạ tầng, CI đẩy image lên ECR qua OIDC, Argo CD sync các service). Sau đó môi trường AWS được gỡ để tránh chi phí và tài khoản ban đầu không còn được dùng. Các lớp bảo mật và độ sẵn sàng thêm vào sau này được kiểm chứng trên cluster kind ở máy local và bằng `terraform plan` chỉ đọc. Ngày 10/10/2026, code hiện tại đã được apply lên một tài khoản mới rồi destroy, cả hai đều không lỗi. @verification trình bày chi tiết.

== Quy ước

- Chữ `monospace` dùng cho tên có thật trong repository hoặc trên AWS: file, resource, lệnh.
- Tên release trong cluster có dạng `<service>-dev` (ví dụ `frontend-dev`); các bảng chỉ ghi phần tên service.
- Đường link trong ngoặc vuông trỏ tới tài liệu AWS làm căn cứ cho nhận định đó.

= Tổng quan hệ thống

== Ứng dụng

Online Boutique là ứng dụng thương mại điện tử mẫu gồm 10 microservice viết bằng 5 ngôn ngữ, gọi nhau qua gRPC. Người dùng xem sản phẩm, thêm vào giỏ hàng (lưu trong Redis) rồi thanh toán; bước checkout gọi tới payment, shipping, email, currency và cart.

#figure(
  table(
    columns: (auto, auto, auto, 1fr, auto, auto),
    [Service], [Ngôn ngữ], [Port], [Nhận lời gọi từ], [CPU req/limit], [Memory req/limit],
    ..facts.services.flatten(),
  ),
  caption: [Các service triển khai vào #raw(facts.namespace) (theo `gitops/dev-eks/values-*.yaml`)],
)

== Repository này bổ sung những gì

Repository bổ sung toàn bộ phần bao quanh ứng dụng để chạy được trên AWS:

#table(
  columns: (28%, 1fr),
  [Lớp], [Nội dung],
  [Infrastructure as Code], [Root module Terraform và 5 module (`vpc`, `eks`, `ecr`, `vpc-endpoints`, `github-oidc-role`).],
  [Đóng gói], [Một Helm chart dùng chung (`helm-charts/`) cho cả 12 release.],
  [Continuous delivery], [Argo CD ApplicationSet sinh một Application cho mỗi service từ `gitops/dev-eks/`.],
  [Continuous integration], [5 workflow theo ngôn ngữ, một workflow Terraform và một workflow security scan.],
  [Bảo mật], [OIDC thay cho access key, Checkov, Trivy, Pod Security Admission, NetworkPolicy.],
  [Tài liệu], [README (tiếng Anh và tiếng Việt), sơ đồ HLD/LLD, tài liệu này và sổ tay vận hành.],
)

== Kiến trúc tổng thể

#figure(image(facts.fig.hld, width: 100%), caption: [Kiến trúc tổng thể trên AWS])

Traffic từ internet đi qua Internet Gateway tới load balancer trong public subnet, rồi được chuyển tới các worker node trong private subnet #link(facts.src.inbound)[[AWS]]. Node truy cập ECR, STS và S3 qua VPC endpoint, phần internet còn lại đi qua một NAT Gateway. Argo CD chạy trong cluster và kéo trạng thái mong muốn từ GitHub.

= Yêu cầu và ràng buộc

== Yêu cầu phi chức năng

#table(
  columns: (20%, 1fr, 30%),
  [Lĩnh vực], [Yêu cầu], [Cách đáp ứng],
  [Bảo mật], [Không có AWS credential dài hạn nào trong repository hay trong GitHub secret.], [IAM role cho GitHub OIDC, IRSA cho VPC CNI.],
  [Bảo mật], [Chỉ code đã review mới tới được AWS; pull request không thể thay đổi hạ tầng.], [PR chỉ có role plan read-only; apply phải được duyệt qua environment `production`.],
  [Bảo mật], [Phát hiện hạ tầng cấu hình sai và image có lỗ hổng trước khi triển khai.], [Checkov chặn trước plan/apply; Trivy quét trước khi push.],
  [Bảo mật], [Pod bị chiếm quyền không gọi được tới service mà nó vốn không gọi.], [Pod hardening, PSA `restricted`, NetworkPolicy cho từng service.],
  [Độ sẵn sàng], [Điểm vào hệ thống chịu được việc mất một pod hoặc một node.], [`frontend` chạy 2–4 replica, có PodDisruptionBudget và rải theo zone/node.],
  [Vận hành], [Dựng lại được trạng thái cluster chỉ từ Git.], [Argo CD tự động sync, prune và self-heal.],
  [Tính di động], [Chuyển sang tài khoản AWS khác không cần sửa code.], [Account ID lấy từ credentials (Terraform) và biến `AWS_ACCOUNT_ID` (CI).],
  [Chi phí], [Môi trường dev dựng lên và gỡ đi khi cần.], [Một NAT Gateway, 3 node `t3.medium`, có hướng dẫn `terraform destroy`.],
)

== Ràng buộc

- *Không sửa `src/`.* Ứng dụng là code upstream. Các phát hiện lint và lỗ hổng cần sửa code thì được giữ hiển thị dưới dạng warning thay vì giấu đi.
- *Một region, một môi trường.* Mọi thứ chạy ở #raw(facts.region) dưới tên `dev`.
- *Repository cá nhân trên GitHub.* Ruleset của repository cá nhân không cho đưa app GitHub Actions vào danh sách bypass (chỉ repository của organization làm được), điều này ảnh hưởng tới GitOps write-back (xem @risks).
- *Chưa có tài khoản AWS tại thời điểm viết.* CI bỏ qua mọi bước cần AWS khi repository variable `AWS_ACCOUNT_ID` chưa được đặt.

= Thiết kế hạ tầng AWS

== Mạng

#figure(
  table(
    columns: (auto, auto, auto, 1fr),
    [Subnet], [AZ ID], [CIDR], [Chứa],
    ..facts.subnets.flatten(),
  ),
  caption: [Quy hoạch subnet, VPC #raw(facts.vpc-cidr) (`cidrsubnet(vpc_cidr, 8, n)`)],
)

- Subnet được đặt theo *AZ ID* (`apse1-az1`, `apse1-az2`) thay vì tên AZ, vì tên AZ ánh xạ tới zone vật lý khác nhau ở mỗi tài khoản.
- Route table public đưa `0.0.0.0/0` ra Internet Gateway. Route table private đưa `0.0.0.0/0` ra NAT Gateway và các prefix S3 vào S3 gateway endpoint.
- *Một NAT Gateway* đặt ở public subnet az1 phục vụ cả hai AZ. Đây là quyết định tiết kiệm chi phí cho dev: nếu az1 gặp sự cố, node ở az2 mất đường ra internet (vẫn truy cập ECR/STS/S3 qua endpoint). Xem quyết định D3.
- VPC endpoint: interface endpoint `ecr.api`, `ecr.dkr`, `sts` có bật private DNS, và gateway endpoint cho S3 (ECR lưu image layer trên S3). Nhờ vậy việc pull image và đổi token IRSA không rời khỏi VPC #link(facts.src.ecr-endpoints)[[AWS]].
- Network ACL cho phép mọi traffic; việc lọc do security group và NetworkPolicy của Kubernetes đảm nhận. NACL mở là finding Checkov đã chấp nhận (@exceptions).

#figure(image(facts.fig.network, width: 100%), caption: [LLD: chi tiết mạng])

#shot("console-vpc-resource-map.png", [VPC đã triển khai trên AWS console: 4 subnet ở hai AZ, route table public và private, Internet Gateway, NAT Gateway và S3 gateway endpoint])

== Security group

#figure(image(facts.fig.sg, width: 100%), caption: [LLD: luồng security group])

- `k8s-elb-*` (Kubernetes tạo cho Service kiểu LoadBalancer) nhận `tcp/80` từ internet.
- Security group của EKS cluster cho phép mọi traffic giữa node và control plane, cộng dải NodePort `tcp/30000-32767` từ load balancer (Kubernetes tự thêm).
- `ecr-endpoint-sg` hiện nhận mọi giao thức từ CIDR của VPC; thực tế chỉ cần `tcp/443`. Việc thu hẹp nằm trong roadmap.

== Compute: Amazon EKS

#table(
  columns: (30%, 1fr),
  [Thiết lập], [Giá trị],
  [Cluster], [#raw(facts.cluster), Kubernetes 1.35],
  [API endpoint], [Public và private. Public mở cho `0.0.0.0/0` (chấp nhận cho dev, xem @exceptions) #link(facts.src.endpoint)[[AWS]]],
  [Control plane log], [Đủ 5 loại: api, audit, authenticator, controllerManager, scheduler],
  [Node group], [Managed, `t3.medium`, `AL2023_x86_64_STANDARD`, on-demand, đĩa 20 GiB, min 1 / desired 3 / max 4, chỉ nằm trong private subnet],
  [Add-on], [VPC CNI bật `enableNetworkPolicy` và có IRSA role riêng, CoreDNS, kube-proxy, Metrics Server (community add-on)],
  [Quyền vào cluster], [Authentication mode `API_AND_CONFIG_MAP`. Người tạo cluster là admin; role console có `AmazonEKSAdminViewPolicy` qua access entry #link(facts.src.access-entries)[[AWS]]],
)

Kubernetes 1.35 hết standard support ngày 27/03/2027 và hết extended support ngày 27/03/2028 #link(facts.src.versions)[[AWS]]. Quy trình nâng phiên bản nằm trong sổ tay vận hành.

#note[`AmazonEKSAdminViewPolicy` chỉ đọc nhưng cho phép role console đọc cả Kubernetes Secret. `AmazonEKSViewPolicy` thì không đọc được Secret nhưng cũng không có quyền xem node, nên console không hiển thị được node #link(facts.src.access-policies)[[AWS]].]

== Container registry: Amazon ECR

- 10 repository, mỗi service một repository, tag `IMMUTABLE`: một tag image (git SHA) không bao giờ bị ghi đè #link(facts.src.ecr-immutable)[[AWS]].
- Lifecycle policy: image untagged hết hạn sau 14 ngày; image không được pull trong 90 ngày chuyển sang lớp lưu trữ archive.
- Scan on push (basic scanning) được cấu hình ở cấp *registry* bằng `aws_ecr_registry_scanning_configuration`, theo khuyến nghị của AWS thay cho thiết lập cấp repository đã deprecated #link(facts.src.ecr-scanning)[[AWS]].
- `force_delete = true` cho phép `terraform destroy` xóa repository còn image. Phù hợp với môi trường dev dùng xong bỏ; nên tắt khi lên production.

#shot("console-ecr-repositories.png", [10 repository ECR: tag immutable, mã hóa AES-256])

== Định danh và phân quyền

#figure(image(facts.fig.cicd, width: 100%), caption: [LLD: CI/CD và IAM OIDC])

GitHub Actions xác thực bằng token ngắn hạn do GitHub OIDC provider `token.actions.githubusercontent.com` cấp. Mỗi role chỉ tin một giá trị claim `sub` cụ thể #link(facts.src.oidc-role)[[AWS]]:

#figure(
  table(
    columns: (auto, auto, 1fr),
    [Role], [`sub` được tin (sau `repo:<repo>:`)], [Quyền],
    ..facts.roles.flatten(),
  ),
  caption: [Các role cho GitHub Actions (`terraform/main.tf`)],
)

- Tin cả hai định dạng `sub` của GitHub: định dạng cũ `owner/repo` và định dạng immutable `owner@id/repo@id` mà GitHub dùng cho repository đổi tên sau 2026-07-15.
- Role apply tin *environment* `production` thay vì nhánh `main`. Environment này chỉ nhận deployment từ `main` và chờ người duyệt, đúng khuyến nghị của AWS khi trust policy dựa vào GitHub environment #link(facts.src.oidc-role)[[AWS]].
- GitHub không cấp OIDC token cho pull request từ fork, nên role plan chỉ được dùng bởi người có quyền ghi vào repository.
- Trong cluster, VPC CNI dùng IRSA (role gắn với `kube-system/aws-node`) thay vì role của node #link(facts.src.irsa)[[AWS]]. Không pod ứng dụng nào cần quyền AWS.

#shot("console-iam-oidc-provider.png", [GitHub OIDC provider trong IAM, audience `sts.amazonaws.com`])
#shot("console-iam-trust-policy.png", [Trust policy của role apply: chỉ environment `production`, ở cả hai định dạng `sub`])

== Terraform state

- State: S3 bucket #raw(facts.state-bucket), key #raw(facts.state-key), có mã hóa, bật versioning.
- Khóa state: bảng DynamoDB #raw(facts.lock-table) (`LockID`). Role plan không có quyền ghi vào bảng này nên plan cho PR chạy với `-lock=false`.
- Bucket và bảng được tạo tay một lần (bootstrap), không do Terraform quản lý.

== Cấu trúc Infrastructure as Code

#table(
  columns: (24%, 1fr),
  [Module], [Tạo ra],
  [`vpc`], [VPC, 2 public + 2 private subnet, Internet Gateway, NAT Gateway, route table, NACL (module con `subnet`, `igw`, `nat_gw`, `route-table`)],
  [`eks`], [Cluster, log group của control plane (lưu 365 ngày), managed node group, 4 add-on, OIDC provider và IRSA role cho VPC CNI],
  [`ecr`], [10 repository, lifecycle policy, cấu hình scanning cấp registry],
  [`vpc-endpoints`], [Interface endpoint `ecr.api`, `ecr.dkr`, `sts`; S3 gateway endpoint; `ecr-endpoint-sg`],
  [`github-oidc-role`], [IAM role có trust policy dựng từ danh sách repository và các giá trị `sub` được phép],
)

Root module nối các module lại với nhau và khai báo GitHub OIDC provider, ba role cùng policy của chúng. Account ID không bao giờ bị hardcode: Terraform lấy từ credentials đang dùng, còn workflow đọc từ repository variable `AWS_ACCOUNT_ID`.

= Thiết kế nền tảng Kubernetes

== Namespace và Pod Security

- Mọi workload chạy trong #raw(facts.namespace). Namespace do một Argo CD Application riêng (`namespaces`) quản lý, có `Delete=false` nên không lần sync nào xóa được nó.
- Pod Security Admission áp profile `restricted` ở chế độ enforce. Pod không có security context hợp lệ bị từ chối ngay lúc admission.
- Monitoring chạy trong `monitoring`; Argo CD trong `argocd`.

== Helm chart dùng chung

Cả 12 release dùng `helm-charts/` (`standard-microservice`). File values của từng service chỉ khai báo phần khác biệt. Chart mặc định đã an toàn:

#table(
  columns: (36%, 1fr),
  [Value], [Mặc định và ý nghĩa],
  [`podSecurityContext`], [`runAsNonRoot`, UID/GID 10001, `seccompProfile: RuntimeDefault`],
  [`securityContext`], [Không leo thang đặc quyền, không privileged, root filesystem chỉ đọc, drop ALL capabilities],
  [`automountServiceAccountToken`], [`false`: không service nào gọi Kubernetes API],
  [`networkPolicy.allowFrom`], [Tên release được phép kết nối; để trống nghĩa là chặn mọi ingress],
  [`networkPolicy.allowFromAnywhere`], [Mở port của service cho mọi nguồn (dùng cho `frontend`)],
  [`autoscaling.*`], [HPA theo CPU, mặc định tắt; min 2, max 4, mục tiêu 70 %],
  [`podDisruptionBudget.*`], [`minAvailable: 1`, chỉ sinh ra khi service chạy từ 2 replica trở lên],
  [`topologySpread.enabled`], [Rải mềm theo zone rồi theo node (`ScheduleAnyway`)],
  [`service.selectorOverride`], [Cho Service trỏ vào pod của release khác (dùng cho `frontend-external`)],
)

`frontend-external` là release có `deployment.enabled: false`, chỉ tạo Service kiểu LoadBalancer (`80 → 8080`) đứng trước các pod `frontend-dev`. Nhờ vậy việc mở ra internet tách biệt khỏi workload.

== Traffic giữa các service

#figure(image(facts.fig.traffic, width: 100%), caption: [Các lời gọi trong cluster được NetworkPolicy cho phép])

Mỗi release có một NetworkPolicy *ingress* chỉ cho phép các caller liệt kê trong `allowFrom`, và chỉ trên port của service. VPC CNI thực thi các policy này #link(facts.src.netpol)[[AWS]]. Egress không bị giới hạn.

== Khả năng chịu lỗi

- `frontend` (điểm vào duy nhất) có HPA theo CPU, từ 2 đến 4 replica. Metrics lấy từ add-on Metrics Server, thứ mà EKS không cài sẵn #link(facts.src.metrics-server)[[AWS]].
- PodDisruptionBudget giữ ít nhất một pod `frontend` khi drain node và khi nâng cấp.
- Các replica được rải qua zone rồi tới node khi scheduler đặt được.
- Các service còn lại chạy 1 replica. `redis-cart` bắt buộc giữ 1: nó dùng volume `emptyDir`, nên giỏ hàng mất khi pod khởi động lại.

== Observability

`kube-prometheus-stack` 84.4.0 (Prometheus, Grafana, Alertmanager, node exporter, kube-state-metrics) được Argo CD deploy vào `monitoring` với `ServerSideApply=true` vì CRD của nó vượt giới hạn kích thước annotation của client-side apply. Control plane log của EKS đẩy về CloudWatch Logs, vào một log group do Terraform tạo với thời hạn lưu 365 ngày, để `terraform destroy` xóa luôn log group này. Hiện chưa có alert rule riêng, dashboard cho từng service, kho log tập trung hay tracing.

= Thiết kế pipeline triển khai

#figure(image(facts.fig.pipeline, width: 100%), caption: [Từ commit tới cluster])

== Continuous integration

Mỗi ngôn ngữ có workflow riêng, chạy khi có push lên `main` vào đường dẫn `src/` của ngôn ngữ đó, hoặc khi chạy tay. `dorny/paths-filter` dựng matrix gồm các service vừa thay đổi, và mỗi service chạy:

+ Lint, unit test và dependency scan (@gates).
+ Đăng nhập AWS bằng role ECR, rồi kiểm tra image của commit này đã có chưa (tag là immutable nên không bao giờ build lại).
+ Build image và quét bằng Trivy (composite action `.github/actions/trivy-scan`): finding HIGH/CRITICAL đẩy lên GitHub code scanning (SARIF), SBOM CycloneDX lưu thành artifact.
+ Push image lên ECR, tag bằng git SHA.
+ Ghi `image.repository` và `image.tag` vào `gitops/dev-eks/values-<service>.yaml` rồi push commit có `[skip ci]` (có vòng retry khi nhiều service chạy cùng lúc).

Khi `AWS_ACCOUNT_ID` chưa được đặt, bước 2, 4 và 5 bị bỏ qua; image được build với tên `local/<service>:<sha>` và vẫn được quét.

#figure(
  table(
    columns: (auto, 1fr, 1fr, 1fr),
    [Stack], [Lint / format], [Test], [Dependency scan],
    ..facts.gates.flatten(),
  ),
  caption: [Quality gate],
) <gates>

Các bước ghi *warning* chỉ sửa được bằng cách đổi code upstream. Chúng dùng `continue-on-error` để hiện thành warning trên mỗi lần chạy thay vì bị giấu đi. Trivy chạy ở chế độ báo cáo (`blocking: 'false'`) cũng vì lý do này.

== Continuous delivery

Một ApplicationSet (`microservices-dev-eks`) sinh 12 Application tên `<service>-dev` từ list generator. Mỗi Application render `helm-charts/` với `gitops/dev-eks/values-<service>.yaml`, đích là namespace #raw(facts.namespace), và tự động sync với `prune` và `selfHeal`. Mọi thay đổi tay trên cluster đều bị đưa về đúng như trong Git. Thêm một service nghĩa là thêm một file values và một phần tử trong list.

== Pipeline hạ tầng

`terraform.yaml` chạy cho pull request và push có thay đổi trong `terraform/` hoặc chính file workflow:

#table(
  columns: (18%, 1fr),
  [Job], [Hành vi],
  [Checkov Scan], [Luôn chạy. Blocking: finding nào không có trong `terraform/.checkov.baseline` sẽ làm run fail.],
  [Terraform Plan], [Chỉ cho pull request từ chính repository này. Role read-only, `fmt -check`, `validate`, `plan -lock=false`.],
  [Terraform Apply], [Chỉ khi push lên `main`. Dùng environment `production`, nên phải chờ người duyệt rồi mới nhận được OIDC token; sau đó `apply -auto-approve`.],
)

Plan và Apply bị bỏ qua khi `AWS_ACCOUNT_ID` chưa được đặt. Lần apply đầu tiên ở một tài khoản mới phải chạy từ máy local, vì các role cho GitHub lúc đó chưa tồn tại.

== Kiểm soát trên repository

- Ruleset `protect-main`: cấm xóa nhánh, cấm force push, bắt buộc qua pull request; admin của repository được bypass. Không đặt status check bắt buộc, vì workflow nào cũng lọc theo path và một check bắt buộc không bao giờ chạy sẽ chặn pull request mãi.
- Environment `production`: chỉ nhận deployment từ nhánh `main`, người duyệt bắt buộc là `khaipd18`.
- `GITHUB_TOKEN` mặc định `contents: read`; job nào cần thêm mới xin thêm (`id-token: write`, `security-events: write`, `contents: write` cho bước write-back).

= Thiết kế bảo mật

== Biện pháp theo từng rủi ro

#table(
  columns: (22%, 1fr, 28%),
  [Rủi ro], [Biện pháp], [Ở đâu],
  [Lộ access key], [OIDC cho GitHub Actions, IRSA trong cluster; không lưu key ở đâu cả], [`terraform/main.tf`, `modules/eks/iam.tf`],
  [Một nhánh hay PR chiếm quyền admin AWS], [Role apply chỉ tin environment `production` (main + người duyệt); role ECR chỉ tin `main`; PR chỉ có plan read-only], [`modules/github-oidc-role`],
  [Terraform cấu hình sai], [Checkov chặn trước plan/apply; finding đã review nằm trong baseline], [`.checkov.yaml`, `terraform/.checkov.baseline`],
  [Image có lỗ hổng], [Trivy quét trước khi push, kết quả lên code scanning, mỗi image có SBOM], [`.github/actions/trivy-scan`],
  [Image bị ghi đè], [Tag immutable, tag = git SHA], [`modules/ecr`],
  [Container bị chiếm quyền], [Non-root, root FS chỉ đọc, drop ALL, seccomp, không mount service account token], [`helm-charts/values.yaml`],
  [Pod không đạt chuẩn], [PSA `restricted` ở chế độ enforce], [`gitops/namespaces/dev-eks.yaml`],
  [Lateral movement], [NetworkPolicy ingress cho từng service theo đúng luồng gọi gRPC], [`helm-charts/templates/networkpolicy.yaml`],
  [Token CI thừa quyền], [Mặc định `contents: read`], [`.github/workflows/*`],
  [Thay đổi chưa review trên `main`], [Ruleset `protect-main`], [Cài đặt GitHub],
)

== Ngoại lệ đã chấp nhận <exceptions>

Các finding Terraform đã review và giữ trong `terraform/.checkov.baseline` (tổng 13):

#table(
  columns: (auto, 1fr, 1fr),
  [Check], [Finding], [Lý do / kế hoạch],
  [`CKV_AWS_39`], [EKS bật public endpoint], [Cần cho kubectl và CI khi không có VPN; giới hạn CIDR hoặc chuyển private (roadmap)],
  [`CKV_AWS_58`], [Chưa dùng KMS key tự quản lý cho secret của EKS], [EKS 1.28+ đã mặc định mã hóa envelope toàn bộ dữ liệu Kubernetes API bằng key do AWS sở hữu #link(facts.src.envelope)[[AWS]]; thêm customer managed key nếu cần tự kiểm soát hay audit key],
  [`CKV_AWS_229`–`232`], [NACL cho phép port 20, 21, 22, 3389 (×2 NACL)], [Việc lọc do security group và NetworkPolicy đảm nhận],
  [`CKV2_AWS_11`], [Tắt VPC flow log], [Chi phí; bật khi lên production],
  [`CKV2_AWS_12`], [Default security group chưa bị giới hạn], [Không resource nào dùng; giới hạn khi lên production],
  [`CKV_AWS_158`], [Log group của control plane chưa dùng KMS key tự quản lý], [CloudWatch Logs mặc định đã mã hóa mọi log group #link(facts.src.logs-encryption)[[AWS]]; thêm KMS key nếu cần tự kiểm soát key],
)

Các check bị bỏ qua toàn cục trong `.checkov.yaml`: `CKV_AWS_163` (scan on push đặt ở cấp registry, check này không nhìn thấy), `CKV_AWS_136` (ECR mặc định mã hóa AES-256), `CKV2_AWS_1` (báo nhầm khi dùng `aws_network_acl_association`).

Manifest Kubernetes render từ chart còn 12 finding Checkov (từ 128 trước khi hardening): image chưa pin theo digest (11) và pull policy của Redis (1). GitHub Actions có 5 finding ở input tự do `custom_tag` của `workflow_dispatch`.

== Chuỗi cung ứng phần mềm

- Image được quét trước khi push; số lỗ hổng HIGH/CRITICAL đã có bản vá được đếm cho từng image ở mỗi lần chạy và hiện trong tab *Security* của GitHub.
- Phiên bản công cụ được pin (Checkov, Trivy, golangci-lint, govulncheck, Terraform, AWS provider). GitHub Actions được pin theo major version, chưa pin theo commit SHA.
- Image chưa được ký và chưa pin theo digest (roadmap).

= Các quyết định thiết kế

#table(
  columns: (5%, 20%, 1fr, 28%),
  [ID], [Quyết định], [Lý do], [Xem xét lại khi],
  [D1], [Dùng IAM role cho GitHub OIDC thay access key], [Không có secret để lộ hay phải xoay vòng; có thể giới hạn tin cậy theo nhánh, PR hoặc environment.], [–],
  [D2], [Apply phải qua GitHub environment], [Chỉ merge thôi thì không đổi được hạ tầng; bước duyệt hiện trên giao diện GitHub và có lịch sử audit.], [Có thêm người duyệt (bật "prevent self-review").],
  [D3], [Một NAT Gateway cho cả hai AZ], [NAT Gateway tính tiền theo giờ và theo GB #link(facts.src.nat-pricing)[[AWS]]; chấp nhận single point of failure ở dev.], [Production: dùng regional NAT gateway, tự trải qua các AZ và không cần public subnet #link(facts.src.regional-nat)[[AWS]].],
  [D4], [Một Helm chart dùng chung], [Thiết lập bảo mật mặc định khai báo một lần; thêm service chỉ cần một file values.], [Có service cần resource mà chart không biểu diễn được.],
  [D5], [ApplicationSet với list generator], [Danh sách những gì được deploy rõ ràng, review trong Git.], [Có nhiều môi trường (chuyển sang matrix hoặc git generator).],
  [D6], [Tag image = git SHA, tag ECR immutable], [Mỗi image đang chạy ứng với đúng một commit; rollback = SHA trước đó.], [–],
  [D7], [Classic Load Balancer từ Service kiểu LoadBalancer], [Không phải cài thêm controller cho dev.], [Cần TLS, định tuyến theo path hoặc WAF (AWS Load Balancer Controller).],
  [D8], [IRSA cho VPC CNI], [Chạy trên mọi phiên bản EKS và có từ đầu.], [EKS Pod Identity giờ là cách đơn giản hơn: không cần OIDC provider cho từng cluster, một trust principal duy nhất #link(facts.src.pod-identity)[[AWS]].],
  [D9], [Khóa state bằng DynamoDB], [Mọi phiên bản Terraform dùng lúc bắt đầu dự án đều hỗ trợ.], [Chuyển sang khóa trực tiếp trên S3 (roadmap).],
  [D10], [Finding của code upstream để ở mức warning], [Code ứng dụng không được bảo trì ở repository này.], [Dependency được nâng cấp (khi đó chuyển gate sang blocking).],
  [D11], [Argo CD cài trong cluster từ manifest upstream], [Không tốn thêm tiền, toàn quyền chọn phiên bản và cấu hình.], [Việc vận hành Argo CD thành gánh nặng: EKS có thể chạy Argo CD dưới dạng capability được quản lý, bên ngoài cluster, tính phí theo giờ #link(facts.src.capabilities)[[AWS]].],
)

= Kiểm chứng <verification>

#table(
  columns: (30%, 1fr),
  [Kiểm tra], [Kết quả],
  [Chạy trên Amazon EKS (05/2026)], [Terraform dựng hạ tầng, image push qua OIDC, Argo CD sync các service. Bằng chứng: commit của bot `14bc93f`, `eb86a9a`, `46e66d5`.],
  [End-to-end trên kind (Kubernetes 1.37)], [11/11 pod ready với security context của chart; xem sản phẩm, giỏ hàng, đổi tiền tệ và checkout đều chạy; PSA từ chối pod không đạt chuẩn; NetworkPolicy chặn 3/3 kết nối trái phép.],
  [HPA và PDB trên cluster kind 3 node], [`frontend` scale 2 → 3 ở 82 % CPU; drain node cuối cùng còn chạy `frontend` bị PDB chặn.],
  [Apply trên tài khoản mới (10/10/2026)], [Tạo 73 resource trong 17 phút; 2 node `Ready` ở hai AZ, 4 add-on `ACTIVE`, Metrics Server trả về số liệu; `terraform destroy` xóa sạch trong 7 phút.],
  [Triển khai đầy đủ (10/10/2026)], [74 resource trên 3 node; Argo CD v3.5.4 sync đủ 14 Application; đặt thử một đơn hàng qua load balancer thành công; trên EKS, PSA từ chối pod không đạt chuẩn và NetworkPolicy chặn 2/2 kết nối không liên quan (do VPC CNI thực thi); sau đó đã destroy.],
  [Terraform], [`fmt` và `validate` pass; plan trên state rỗng: 74 resource sẽ được tạo, không lỗi.],
  [Checkov 3.3.22], [Terraform 0 finding mới (12 trong baseline); Kubernetes 999 pass / 12 fail; GitHub Actions 5 fail.],
  [CI không có AWS (08/10/2026)], [Cả 5 workflow theo ngôn ngữ xanh; bước AWS được bỏ qua; kết quả Trivy được tải lên cho cả 10 image.],
)

#shot("terminal-security.png", [Các lớp bảo mật trên EKS: PSA từ chối pod không đạt chuẩn; NetworkPolicy chỉ cho pod không liên quan vào `frontend`])
#shot("shop-order-complete.png", [Trang xác nhận đơn hàng của shop chạy trên EKS], width: 80%)

= Rủi ro, hạn chế và roadmap <risks>

== Rủi ro đã biết

#table(
  columns: (26%, 1fr, 24%),
  [Rủi ro], [Ảnh hưởng], [Giảm thiểu hiện tại],
  [Bot CI bị ruleset của `main` chặn], [Khi đã cấu hình AWS, lần push GitOps write-back bị từ chối và image mới không được deploy.], [Chưa có: cần deploy key trong danh sách bypass hoặc write-back qua PR.],
  [Chỉ một NAT Gateway], [Mất az1 thì cả hai AZ mất đường ra internet.], [Traffic tới ECR/STS/S3 đi qua endpoint.],
  [10 service chỉ có 1 replica], [Pod khởi động lại gây gián đoạn ngắn cho tính năng đó.], [Kubernetes tự khởi động lại pod; `frontend` có từ 2 replica.],
  [Dữ liệu giỏ hàng trong `emptyDir`], [Giỏ hàng mất khi `redis-cart` khởi động lại.], [Chấp nhận cho bản demo.],
  [Lỗ hổng đã biết trong image], [Một số image có finding CRITICAL đã có bản vá.], [Hiện trong tab Security; có thể chuyển gate sang blocking.],
  [EKS public endpoint mở ra internet], [API server truy cập được từ mọi nơi (vẫn cần xác thực IAM).], [Xác thực IAM; đã bật audit log.],
)

== Roadmap <roadmap>

Theo thứ tự ưu tiên:

+ Khôi phục GitOps write-back khi có ruleset trên `main` (deploy key trong danh sách bypass, hoặc bot mở pull request).
+ Nâng dependency của các service (Dependabot), rồi chuyển Trivy, `govulncheck` và `npm audit` sang blocking.
+ Giới hạn EKS public endpoint hoặc chuyển sang private endpoint.
+ Thu hẹp `ecr-endpoint-sg` về `tcp/443` từ VPC.
+ Thay NAT Gateway duy nhất bằng regional NAT gateway.
+ Cân nhắc dùng EKS capability cho Argo CD (quyết định D11).
+ External Secrets Operator với AWS Secrets Manager.
+ Pin image theo digest, ký bằng cosign và verify ở admission.
+ AWS Load Balancer Controller có TLS thay cho Classic Load Balancer.
+ Môi trường staging và production có luồng promote, canary bằng Argo Rollouts.
+ Alert rule theo SLO và dashboard Grafana cho từng service.
+ Khóa state trực tiếp trên S3 thay cho DynamoDB; cân nhắc EKS Pod Identity thay cho IRSA.

#heading(numbering: none)[Phụ lục A. Phiên bản]

#table(
  columns: (32%, 28%, 1fr),
  [Thành phần], [Phiên bản], [Khai báo ở],
  ..facts.versions.flatten(),
)

#heading(numbering: none)[Phụ lục B. Thuật ngữ]

#table(
  columns: (22%, 1fr),
  [Thuật ngữ], [Ý nghĩa],
  [ApplicationSet], [Resource của Argo CD sinh nhiều Application từ một template và một generator.],
  [GitOps write-back], [CI commit tag image mới vào Git để Argo CD deploy.],
  [HPA / PDB], [HorizontalPodAutoscaler / PodDisruptionBudget.],
  [IRSA], [IAM Roles for Service Accounts: pod assume IAM role qua OIDC provider của cluster.],
  [OIDC], [OpenID Connect. GitHub cấp một token có chữ ký cho mỗi job; AWS STS đổi token đó lấy credential tạm thời.],
  [PSA], [Pod Security Admission, admission controller có sẵn để áp Pod Security Standards.],
  [SBOM], [Software Bill of Materials (danh mục thành phần phần mềm); ở đây theo định dạng CycloneDX.],
  [Claim `sub`], [Subject của GitHub OIDC token, ví dụ `repo:owner/repo:ref:refs/heads/main`.],
)
