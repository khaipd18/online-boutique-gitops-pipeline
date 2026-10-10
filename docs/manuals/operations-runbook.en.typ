#import "lib/template.typ": manual, callout, palette, shot
#import "lib/facts.typ" as facts

#let note = callout.with("note", lang: "en")
#let warning = callout.with("warning", lang: "en")
#let important = callout.with("important", lang: "en")
#let tip = callout.with("tip", lang: "en")

#show: manual.with(
  title: "Operations Runbook",
  subtitle: "How to run, check, change and stop the platform",
  doc-id: "OBE-RUN-001",
  version: "2.0",
  date: facts.doc-date,
  status: "Approved for the dev environment",
  owner: "khaipd18 (DevOps / Cloud)",
  audience: "Engineers who deploy or operate the platform",
  classification: "Internal",
  repository: facts.repo-url,
  lang: "en",
  revisions: (
    ("1.0", "2026-10-09", "First issue.", "khaipd18"),
    ("1.1", "2026-10-10", "First run on the new account; managed control plane log group.", "khaipd18"),
    ("1.2", "2026-10-10", "Screenshots from the full EKS deployment; IR-15.", "khaipd18"),
    ("2.0", facts.doc-date, "Rewritten to be shorter: the main tasks in plain steps, all problems in one table, advanced topics moved to the appendix.", "khaipd18"),
  ),
  related: (
    [OBE-TDD-001 Technical Design Document: why the platform is built this way],
    [README.md: project summary and how to test locally with kind],
  ),
)

= Start here

== What runs where

#table(
  columns: (30%, 1fr),
  [Part], [Where it lives],
  [Infrastructure (VPC, EKS, ECR, IAM)], [AWS #raw(facts.region), created by Terraform from `terraform/`],
  [Kubernetes cluster], [#raw(facts.cluster), 3 `t3.medium` nodes],
  [Shop (12 services)], [Namespace #raw(facts.namespace), deployed by Argo CD from `gitops/dev-eks/`],
  [Argo CD], [Namespace `argocd`, inside the cluster],
  [Monitoring (Prometheus, Grafana)], [Namespace `monitoring`],
  [CI/CD], [GitHub Actions in the repository],
)

== Three rules

+ *Change things through Git.* Argo CD puts the cluster back to what Git says, so a manual `kubectl` change is undone within minutes.
+ *Infrastructure changes go through a pull request.* The Terraform apply waits for your approval in GitHub.
+ *Stop the environment when you are done.* It costs about 0.40 USD per hour plus the load balancer (Appendix C).

== Tools you need

AWS CLI v2, Terraform 1.14+, `kubectl`, Helm, GitHub CLI (`gh`). Log in to AWS with the account's profile and check it:

```bash
aws sts get-caller-identity          # shows the account you are using
aws eks update-kubeconfig --region ap-southeast-1 --name khaipd18-eks-cluster
kubectl get nodes                    # 3 nodes, all Ready
```

#note[Only the identity that created the cluster is cluster admin. The role used in the AWS console gets read-only access automatically (Terraform), so the EKS console can show pods and nodes.]

= Main tasks

== Start the environment

*Time:* about 45 minutes. *Cost starts at step 3.*

+ *Tell GitHub which AWS account to use:*
  ```bash
  gh variable set AWS_ACCOUNT_ID --body <account-id>
  ```
+ *Create the place where Terraform keeps its state* (only once per account):
  ```bash
  aws s3api create-bucket --bucket <state-bucket> --region ap-southeast-1 \
    --create-bucket-configuration LocationConstraint=ap-southeast-1
  aws s3api put-bucket-versioning --bucket <state-bucket> \
    --versioning-configuration Status=Enabled
  aws dynamodb create-table --table-name <lock-table> --region ap-southeast-1 \
    --attribute-definitions AttributeName=LockID,AttributeType=S \
    --key-schema AttributeName=LockID,KeyType=HASH --billing-mode PAY_PER_REQUEST
  ```
  The names must match `terraform/backend.tf`.
+ *Create the infrastructure* (about 17 minutes):
  ```bash
  cd terraform
  terraform init
  terraform plan -out tfplan     # read it: 74 resources to add
  terraform apply tfplan
  ```
+ *Install Argo CD and tell it what to deploy:*
  ```bash
  aws eks update-kubeconfig --region ap-southeast-1 --name khaipd18-eks-cluster
  kubectl create namespace argocd
  kubectl apply -n argocd --server-side -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
  kubectl apply -f gitops/argocd/namespaces.yaml
  kubectl apply -f gitops/argocd/applicationset.yaml
  kubectl apply -f gitops/argocd/monitoring.yaml --server-side
  ```
+ *Build the images.* The `main` branch rule blocks the CI bot, so switch it off for a moment:
  ```bash
  gh api -X PUT repos/khaipd18/online-boutique-gitops-pipeline/rulesets/24705847 -f enforcement=disabled
  for w in go dotnet java node py; do gh workflow run $w-services-ci.yaml --ref main; done
  # wait until the 5 runs are green: gh run list --limit 5
  gh api -X PUT repos/khaipd18/online-boutique-gitops-pipeline/rulesets/24705847 -f enforcement=active
  ```
+ *Check it works:* follow the next section. Everything should look like the pictures there.

== Check that everything is healthy

Run these four commands:

```bash
kubectl get nodes                       # 3 nodes, all Ready
kubectl -n argocd get applications      # 14 apps, all Synced and Healthy
kubectl -n dev-eks get pods             # all Running, restarts not growing
kubectl -n dev-eks get hpa              # frontend CPU below 70%
```

#shot("terminal-daily.png", [What a healthy cluster looks like])

Open the shop: get its address with
`kubectl -n dev-eks get svc frontend-external-dev`, open the `EXTERNAL-IP` hostname in a browser and place an order.

#shot("shop-order-complete.png", [A test order went through: the whole shop works], width: 75%)

*Open the web consoles* (each command keeps running; open the address in your browser):

#table(
  columns: (18%, 1fr, 22%),
  [Console], [Command], [Address],
  [Argo CD], [`kubectl -n argocd port-forward svc/argocd-server 8080:443`], [https://localhost:8080],
  [Grafana], [`kubectl -n monitoring port-forward svc/kube-prometheus-stack-grafana 3000:80`], [http://localhost:3000],
)

User `admin`. Passwords:
```bash
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d; echo
kubectl -n monitoring get secret kube-prometheus-stack-grafana -o jsonpath='{.data.admin-password}' | base64 -d; echo
```

#shot("argocd-applications.png", [Argo CD: every application Synced and Healthy])
#shot("grafana-namespace-pods.png", [Grafana, dashboard "Kubernetes / Compute Resources / Namespace (Pods)": CPU and memory per pod])
#shot("console-eks-nodes.png", [AWS console, EKS → Compute: three nodes Ready])

== Release a new version of a service

+ Merge your change under `src/<service>/` into `main`.
+ GitHub Actions tests, builds and scans the image, pushes it to ECR and writes the new tag into `gitops/dev-eks/values-<service>.yaml`.
+ Argo CD sees the new tag within about 3 minutes and updates the pods.

Check: `kubectl -n dev-eks rollout status deploy/<service>-dev`

#shot("github-ci-run.png", [A successful CI run in GitHub Actions])

== Roll back a service

Every image tag is a commit, so going back means restoring the previous tag in Git:

```bash
git log --oneline -- gitops/dev-eks/values-<service>.yaml   # find the bad tag commit
git revert <commit>                                          # then push or open a PR
```

#warning[Do not use `kubectl set image` or `kubectl rollout undo`. Argo CD will put the bad version back.]

== Change settings or scale a service

All settings of a service are in `gitops/dev-eks/values-<service>.yaml`: environment variables, CPU and memory, number of replicas, autoscaling, and which services may call it (`networkPolicy.allowFrom`).

+ Edit the file in a branch.
+ Check the result: `helm template <service>-dev helm-charts -f gitops/dev-eks/values-<service>.yaml`
+ Open a pull request and merge it. Argo CD applies it.

#tip[If a service starts calling another one, add the caller to the other service's `allowFrom`, otherwise the call is blocked.]

To change the number of *nodes*, edit `eks_node_group_scaling_config` in `terraform/variables.tf` and follow the next section.

#shot("argocd-frontend-tree.png", [Argo CD shows everything one service owns: Deployment, pods, HPA, NetworkPolicy, PodDisruptionBudget])

== Change the infrastructure

+ Edit `terraform/` in a branch and open a pull request.
+ GitHub runs Checkov (security check) and `terraform plan`. Read the plan in the job log.
+ Merge the pull request.
+ The *Terraform Apply* job waits. In GitHub: *Actions* → the run → *Review deployments* → *production* → *Approve*.

#important[Only approve a plan you have read. The apply runs with full admin rights.]

== Stop the environment

+ Remove the applications and the load balancer first (Terraform cannot delete the VPC while the load balancer exists):
  ```bash
  kubectl delete -f gitops/argocd/applicationset.yaml
  kubectl -n dev-eks delete svc frontend-external-dev --ignore-not-found
  ```
+ Delete the infrastructure (about 10 minutes):
  ```bash
  cd terraform && terraform destroy
  ```
+ Tell CI there is no AWS account any more: `gh variable delete AWS_ACCOUNT_ID`

Check: `aws eks list-clusters --region ap-southeast-1` returns an empty list. The state bucket and lock table stay; they cost almost nothing.

= When something goes wrong

Find the symptom in the table, then apply the fix. The command in the middle column usually shows the reason.

#table(
  columns: (26%, 1fr, 1fr),
  [Symptom], [Likely reason / how to see it], [Fix],
  [CI fails at "Configure AWS credentials"], [Wrong `AWS_ACCOUNT_ID`, or the IAM roles do not exist yet. `gh variable list`], [Fix the variable, or create the roles with the first `terraform apply`],
  [CI fails at "Update GitOps" with `GH013`], [The `main` rule blocks the bot], [Switch the rule off while CI runs (Start the environment, step 5)],
  [Terraform: `Error acquiring the state lock`], [An earlier run stopped half-way. Make sure nothing else runs: `gh run list`], [`terraform force-unlock <lock-id>`],
  [Terraform Apply job is *Waiting*], [It needs your approval], [Approve it in GitHub (Change the infrastructure)],
  [Argo CD app *OutOfSync* or *Degraded*], [Bad values or a pod that does not start. `kubectl -n argocd describe application <app>`], [Fix the values in Git],
  [Pod in `ImagePullBackOff`], [The image tag is not in ECR. `kubectl -n dev-eks describe pod <pod>`], [Run the service's CI, or roll back],
  [Pod in `CrashLoopBackOff` / `OOMKilled`], [Wrong setting or not enough memory. `kubectl -n dev-eks logs <pod> --previous`], [Fix the values or roll back],
  [Pod `forbidden: violates PodSecurity`], [The values remove the safe security settings], [Remove that override from the values file],
  [Calls between services time out], [The caller is not in `allowFrom`. `kubectl -n dev-eks get networkpolicy`], [Add the caller to `allowFrom`],
  [Shop address does not open], [Load balancer still starting, or `frontend` is down. `kubectl -n dev-eks get pods`], [Wait a few minutes; fix `frontend`],
  [Pods stay `Pending`], [Not enough room on the nodes. `kubectl describe pod <pod>`], [Reduce replicas or add a node],
  [HPA shows `<unknown>`], [Metrics Server not ready. `kubectl top pods -n dev-eks`], [Re-apply Terraform (it installs Metrics Server)],
  [`kubectl drain` never finishes], [The PodDisruptionBudget keeps one `frontend` pod alive (on purpose)], [Add a node so the pod can move, then retry],
  [Shopping carts are empty], [`redis-cart` restarted; carts are not saved to disk], [Expected in this demo],
  [EKS console shows "Data unavailable"], [The console role has no access in the cluster], [Re-apply Terraform (it gives the console role read access)],
)

#shot("terminal-security.png", [Security working as designed: a pod without security settings is rejected; a pod that is not allowed cannot reach `paymentservice` or `redis-cart`])

#important[If users are affected (shop down, checkout broken), roll back first and investigate after. Write down what happened in a GitHub issue.]

#heading(numbering: none)[Appendix]

#heading(level: 2, numbering: none)[A. Upgrade Kubernetes]

Kubernetes 1.35 is supported by EKS until 27 March 2027 #link(facts.src.versions)[[AWS]]. Upgrade one version at a time:

+ Check *EKS console → Upgrade insights*: every check must be *Passing*.
+ Change `eks_k8s_version` in Terraform and apply it. This upgrades the control plane.
+ Upgrade the nodes; Terraform does not do it #link(facts.src.nodegroup-update)[[AWS]]:
  ```bash
  aws eks update-nodegroup-version --cluster-name khaipd18-eks-cluster \
    --nodegroup-name khaipd18-eks-cluster-node-group --kubernetes-version <version>
  ```
+ Update the add-on versions (`eks_*_version` variables). List the versions with
  `aws eks describe-addon-versions --addon-name <name> --kubernetes-version <version>`.

#shot("console-eks-upgrade-insights.png", [EKS upgrade insights: all checks passing])

#heading(level: 2, numbering: none)[B. Security findings]

- *Checkov (Terraform):* fix the code if you can. If a finding is acceptable, write down why and update the baseline in a pull request:
  `checkov --config-file .checkov.yaml -d terraform --framework terraform --create-baseline`
- *Trivy (images):* findings are in GitHub → *Security* → *Code scanning*. They come from the application code in `src/`, which this repository does not change, so they are reported but do not block CI.

#shot("github-code-scanning.png", [GitHub code scanning: Trivy findings per image])

#heading(level: 2, numbering: none)[C. Cost]

About *0.40 USD per hour* while the environment runs, before the load balancer and small items (on-demand prices in #raw(facts.region) from the AWS Price List API): EKS control plane 0.10, three `t3.medium` nodes 0.16, six interface endpoint ENIs 0.08, NAT Gateway 0.06. See the real spend in AWS Cost Explorer. Stop the environment when it is not needed.

#heading(level: 2, numbering: none)[D. Recovery]

#table(
  columns: (30%, 1fr),
  [Lost], [How to get it back],
  [The whole cluster or account], [Start the environment again: everything is rebuilt from Git in about 45 minutes],
  [Terraform state], [The state bucket keeps old versions: restore the previous version of #raw(facts.state-key)],
  [A bad deployment], [Roll back the service],
  [Shopping carts, Grafana history], [Not saved; they are lost],
)

#heading(level: 2, numbering: none)[E. Services and ports]

#table(
  columns: (auto, auto, auto, 1fr, auto, auto),
  [Service], [Language], [Port], [Accepts calls from], [CPU req/limit], [Memory req/limit],
  ..facts.services.flatten(),
)

#heading(level: 2, numbering: none)[F. Versions]

#table(
  columns: (32%, 28%, 1fr),
  [Component], [Version], [Defined in],
  ..facts.versions.flatten(),
)
