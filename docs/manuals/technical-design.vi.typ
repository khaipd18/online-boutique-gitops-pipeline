#import "lib/template.typ": manual, callout, palette, shot
#import "lib/facts.typ" as facts

#let note = callout.with("note", lang: "vi")

#set heading(supplement: [Mục])
#set figure(supplement: it => if it.func() == table { [Bảng] } else { [Hình] })

#show: manual.with(
  title: "Tài liệu thiết kế kỹ thuật",
  subtitle: "Hệ thống được xây thế nào và vì sao",
  doc-id: "OBE-TDD-001-VI",
  version: "2.0",
  date: facts.doc-date,
  status: "Đã duyệt cho môi trường dev",
  owner: "khaipd18 (DevOps / Cloud)",
  audience: "Kỹ sư Cloud và DevOps, người review",
  classification: "Nội bộ",
  repository: facts.repo-url,
  lang: "vi",
  revisions: (
    ("1.0", "2026-10-09", "Phát hành lần đầu.", "khaipd18"),
    ("1.1", "2026-10-10", "Chạy thật trên tài khoản mới; Terraform quản lý log group.", "khaipd18"),
    ("1.2", "2026-10-10", "Triển khai đầy đủ trên EKS, ảnh chụp, access entry, ba node, quyết định D11.", "khaipd18"),
    ("2.0", facts.doc-date, "Viết lại cho ngắn gọn: mỗi mảng một trang, bỏ phần lặp.", "khaipd18"),
  ),
  related: (
    [OBE-RUN-001-VI Sổ tay vận hành: cách chạy và xử lý sự cố],
    [Bản tiếng Anh: `docs/manuals/technical-design.en.pdf` (OBE-TDD-001)],
    [`docs/infrastructure/`: sơ đồ HLD/LLD sửa được và YAML spec tương ứng],
  ),
)

= Tổng quan

*Đây là gì.* Online Boutique của Google (10 microservice viết bằng 5 ngôn ngữ, gọi nhau qua gRPC) chạy trên Amazon EKS. Toàn bộ phần bao quanh được xây trong repository này: hạ tầng dạng code, CI/CD, GitOps và các lớp bảo mật. Code ứng dụng trong `src/` là code upstream và được giữ nguyên.

*Mục tiêu.*
- Không có access key AWS dài hạn ở đâu cả; chỉ code đã review mới thay đổi được AWS.
- Phát hiện cấu hình sai và image có lỗ hổng trước khi deploy.
- Dựng lại được cluster chỉ từ Git; chuyển sang tài khoản AWS khác không cần sửa code.
- Môi trường dev dựng lên và tắt đi rẻ, nhanh.

*Hiện trạng.* Đã triển khai và kiểm tra end-to-end trên EKS ngày 10/10/2026 (mục 7), sau đó destroy để tiết kiệm chi phí. Có một môi trường (`dev`) ở #raw(facts.region).

#figure(image(facts.fig.hld, width: 100%), caption: [Kiến trúc tổng thể])

Người dùng vào shop qua load balancer ở public subnet; các worker node nằm trong private subnet. Node truy cập ECR, STS và S3 qua VPC endpoint, ra internet qua một NAT Gateway. Argo CD chạy trong cluster và kéo trạng thái mong muốn từ GitHub về.

= Hạ tầng AWS

== Mạng

#table(
  columns: (auto, auto, auto, 1fr),
  [Subnet], [AZ ID], [CIDR], [Chứa],
  ..facts.subnets.flatten(),
)

- VPC #raw(facts.vpc-cidr) trên hai AZ, đặt theo AZ ID vì tên AZ mỗi tài khoản một khác.
- Một NAT Gateway dùng chung cho hai AZ để tiết kiệm (quyết định D3).
- VPC endpoint cho `ecr.api`, `ecr.dkr`, `sts` và S3, nên việc pull image không ra khỏi VPC #link(facts.src.ecr-endpoints)[[AWS]].
- Lọc traffic bằng security group và NetworkPolicy của Kubernetes; network ACL cho qua tất cả.

#figure(image(facts.fig.network, width: 100%), caption: [LLD: chi tiết mạng])

== EKS, ECR và state

#table(
  columns: (22%, 1fr),
  [Thành phần], [Thiết kế],
  [EKS cluster], [#raw(facts.cluster), Kubernetes 1.35 (standard support tới 27/03/2027 #link(facts.src.versions)[[AWS]]); API endpoint public và private; mọi control plane log đẩy về CloudWatch (lưu 365 ngày)],
  [Node], [Managed node group, 3 × `t3.medium` (min 1, max 4), Amazon Linux 2023, chỉ nằm trong private subnet],
  [Add-on], [VPC CNI có thực thi NetworkPolicy, CoreDNS, kube-proxy, Metrics Server],
  [Quyền vào cluster], [EKS access entry: người tạo cluster là admin, role console chỉ đọc (`AmazonEKSAdminViewPolicy`) #link(facts.src.access-entries)[[AWS]]],
  [ECR], [10 repository, tag immutable (tag = git SHA), scan on push, lifecycle policy dọn image cũ #link(facts.src.ecr-immutable)[[AWS]]],
  [Terraform state], [S3 bucket #raw(facts.state-bucket) (có versioning, mã hóa) và bảng khóa DynamoDB; tạo tay một lần],
)

Terraform chia thành 5 module: `vpc`, `eks`, `ecr`, `vpc-endpoints` và `github-oidc-role`. Account ID không bao giờ được ghi cứng trong code.

== Quyền cho CI (GitHub OIDC)

GitHub Actions nhận credential AWS ngắn hạn từ GitHub OIDC provider. Mỗi role chỉ tin đúng một giá trị `sub` của token #link(facts.src.oidc-role)[[AWS]]:

#table(
  columns: (auto, auto, 1fr),
  [Role], [`sub` được tin], [Dùng để],
  [`github-actions-ecr-oidc-role`], [`ref:refs/heads/main`], [CI push image],
  [`github-actions-terraform-plan-oidc-role`], [`pull_request`], [`terraform plan` chỉ đọc cho PR],
  [`github-actions-terraform-oidc-role`], [`environment:production`], [`terraform apply`, chỉ sau khi có người duyệt],
)

#figure(image(facts.fig.cicd, width: 100%), caption: [LLD: CI/CD và IAM OIDC])

= Nền tảng Kubernetes

Mọi service chạy trong namespace #raw(facts.namespace). Tất cả release dùng chung một Helm chart (`helm-charts/`); file values của từng service chỉ ghi phần khác biệt.

#table(
  columns: (auto, auto, auto, 1fr, auto, auto),
  [Service], [Ngôn ngữ], [Port], [Nhận lời gọi từ], [CPU req/limit], [Memory req/limit],
  ..facts.services.flatten(),
)

*An toàn mặc định.* Pod chạy bằng user không phải root, file system chỉ đọc, không có Linux capability, không mount service account token. Pod Security Admission (`restricted`) từ chối mọi pod không theo các quy tắc này.

*Ai được gọi ai.* Mỗi service có một NetworkPolicy chỉ cho các bên gọi được liệt kê trong file values (`allowFrom`) đi vào.

#figure(image(facts.fig.traffic, width: 100%), caption: [Các lời gọi được phép giữa các service])

*Khả năng chịu lỗi.* `frontend` chạy 2–4 replica với autoscaler theo CPU (HPA), PodDisruptionBudget và rải qua các zone. Các service còn lại chạy một replica. `redis-cart` giữ giỏ hàng trong bộ nhớ nên giỏ hàng mất khi nó khởi động lại.

*Monitoring.* Prometheus và Grafana (`kube-prometheus-stack`) trong namespace `monitoring`; control plane log trên CloudWatch. Chưa có alert riêng.

= Pipeline triển khai

#figure(image(facts.fig.pipeline, width: 100%), caption: [Từ commit tới cluster])

*CI (mỗi ngôn ngữ một workflow).* Với mỗi service thay đổi: lint, test và dependency scan → build image → quét bằng Trivy (kết quả lên tab Security của GitHub, lưu SBOM) → push lên ECR với tag là git SHA → ghi tag vào `gitops/dev-eks/`. Khi chưa có biến `AWS_ACCOUNT_ID`, CI vẫn lint, test, build, quét và bỏ qua các bước AWS.

#table(
  columns: (auto, 1fr, 1fr, 1fr),
  [Stack], [Lint / format], [Test], [Dependency scan],
  ..facts.gates.flatten(),
)

Các bước ghi *warning* cần sửa code upstream mới hết, nên chỉ hiện cảnh báo chứ không làm run fail.

*CD.* Một Argo CD ApplicationSet tạo 12 Application từ `gitops/dev-eks/` và giữ chúng luôn đồng bộ: thay đổi trong Git được áp dụng, thay đổi tay bị hoàn lại.

*Hạ tầng.* Pull request sửa `terraform/` sẽ chạy Checkov (chặn nếu lỗi) và `terraform plan` chỉ đọc. Sau khi merge, `terraform apply` chờ người duyệt trong GitHub environment `production`. Nhánh `main` được bảo vệ bằng ruleset `protect-main`.

= Bảo mật

#table(
  columns: (28%, 1fr),
  [Rủi ro], [Biện pháp],
  [Lộ access key], [Không có key: CI dùng GitHub OIDC, VPC CNI dùng IRSA],
  [Thay đổi chưa review tới được AWS], [PR chỉ có role chỉ đọc; apply cần `main` và người duyệt],
  [Terraform cấu hình sai], [Checkov chặn trước plan và apply],
  [Image có lỗ hổng], [Trivy quét trước khi push; finding lên code scanning; mỗi image có SBOM],
  [Image bị ghi đè], [Tag ECR immutable],
  [Container bị chiếm quyền], [Không chạy root, file system chỉ đọc, không capability, PSA `restricted`],
  [Đi ngang giữa các service], [NetworkPolicy cho từng service],
)

*Finding đã chấp nhận.* 13 finding của Checkov đã được review và giữ trong `terraform/.checkov.baseline`:

#table(
  columns: (auto, 1fr),
  [Check], [Lý do chấp nhận],
  [`CKV_AWS_39` EKS endpoint public], [Cần khi không có VPN; sẽ giới hạn sau (roadmap)],
  [`CKV_AWS_58`, `CKV_AWS_158` chưa dùng KMS key riêng], [EKS và CloudWatch Logs đã mã hóa dữ liệu bằng key của AWS #link(facts.src.envelope)[[AWS]]],
  [`CKV_AWS_229`–`232` NACL mở port], [Lọc traffic bằng security group và NetworkPolicy],
  [`CKV2_AWS_11` chưa bật VPC flow log], [Chi phí; bật khi lên production],
  [`CKV2_AWS_12` default security group], [Không resource nào dùng],
)

= Quyết định thiết kế

#table(
  columns: (5%, 30%, 1fr),
  [ID], [Quyết định], [Lý do / khi nào xem lại],
  [D1], [GitHub OIDC thay cho access key], [Không có gì để lộ hay phải xoay vòng.],
  [D2], [Apply phải được duyệt trong GitHub environment], [Chỉ merge thôi thì không đổi được hạ tầng.],
  [D3], [Một NAT Gateway cho hai AZ], [Rẻ hơn cho dev. Lên production thì dùng regional NAT gateway #link(facts.src.regional-nat)[[AWS]].],
  [D4], [Một Helm chart cho mọi service], [Thiết lập bảo mật viết một lần; thêm service chỉ cần một file values.],
  [D5], [ApplicationSet với danh sách cố định], [Những gì được deploy nhìn thấy rõ trong Git. Xem lại khi có nhiều môi trường.],
  [D6], [Tag image = git SHA, immutable], [Image nào đang chạy cũng ứng với một commit; rollback = SHA trước đó.],
  [D7], [Classic Load Balancer từ một Service], [Không cần cài thêm controller cho dev. Xem lại khi cần TLS hay WAF.],
  [D8], [IRSA cho VPC CNI], [Chạy được ở mọi nơi. EKS Pod Identity giờ đơn giản hơn #link(facts.src.pod-identity)[[AWS]].],
  [D9], [Khóa state bằng DynamoDB], [Hợp với mọi phiên bản Terraform; sau này chuyển sang khóa trên S3.],
  [D10], [Lỗ hổng của code upstream để ở mức warning], [Code ứng dụng không được bảo trì ở đây.],
  [D11], [Argo CD cài trong cluster], [Miễn phí và toàn quyền kiểm soát. EKS cũng có thể chạy Argo CD dưới dạng capability được quản lý #link(facts.src.capabilities)[[AWS]].],
  [D12], [Mặc định ba node], [Toàn bộ hệ thống cần khoảng 37 pod; hai node `t3.medium` không đủ #link(facts.src.max-pods)[[AWS]].],
)

= Kiểm chứng <verification>

#table(
  columns: (28%, 1fr),
  [Kiểm tra], [Kết quả],
  [Triển khai đầy đủ trên EKS (10/10/2026)], [74 resource trên 3 node; Argo CD sync đủ 14 app; đặt thử đơn hàng thành công; PSA từ chối pod sai chuẩn và NetworkPolicy chặn 2/2 kết nối không được phép; sau đó đã destroy],
  [Cluster kind (local)], [Mọi pod ready; checkout chạy; HPA scale 2 → 3 khi có tải; PDB chặn drain node cuối cùng chạy `frontend`],
  [Terraform], [`fmt`, `validate`, Checkov đều pass; plan = 74 resource],
  [CI không có AWS], [Cả 5 pipeline theo ngôn ngữ xanh; có kết quả Trivy cho cả 10 image],
  [Lần chạy EKS đầu tiên (05/2026)], [Image push qua OIDC và được Argo CD sync (commit của bot `14bc93f`, `eb86a9a`, `46e66d5`)],
)

#shot("terminal-security.png", [Kiểm tra bảo mật trên EKS: PSA từ chối pod sai chuẩn; NetworkPolicy chặn các lời gọi không được phép])

= Rủi ro và roadmap <risks>

*Rủi ro đã biết:* ruleset của `main` chặn commit GitOps của bot CI (phải tạm tắt khi bootstrap); một NAT Gateway là điểm lỗi đơn; mười service chỉ có một replica; giỏ hàng mất khi `redis-cart` khởi động lại; vài image có lỗ hổng đã biết; EKS API endpoint mở ra internet (vẫn cần xác thực IAM).

*Roadmap*, theo thứ tự:
+ Cho bot CI cập nhật `gitops/` khi có ruleset (deploy key hoặc pull request).
+ Nâng dependency của các service, rồi chuyển các gate lỗ hổng sang chặn.
+ Giới hạn EKS public endpoint; thu hẹp `ecr-endpoint-sg` về `tcp/443`.
+ Regional NAT gateway; AWS Load Balancer Controller có TLS.
+ External Secrets với AWS Secrets Manager; ký image và pin theo digest.
+ Môi trường staging và production; alert theo SLO.
+ Khóa state trên S3; cân nhắc EKS Pod Identity và Argo CD capability.

#heading(numbering: none)[Phụ lục. Phiên bản]

#table(
  columns: (32%, 28%, 1fr),
  [Thành phần], [Phiên bản], [Khai báo ở],
  ..facts.versions.flatten(),
)
