# This Terraform module creates an AWS IAM role that can be assumed by GitHub Actions using OpenID Connect (OIDC).
# The role will have permissions to access specified ECR repositories, allowing GitHub Actions workflows to authenticate and interact with AWS resources securely.
data "aws_iam_policy_document" "github_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [var.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    # The "sub" claim must exactly match one of the allowed repository/trigger combinations,
    # e.g. repo:owner/repo:ref:refs/heads/main or repo:owner/repo:pull_request
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = flatten([for repo in var.github_repos : [for subject in var.allowed_subjects : "repo:${repo}:${subject}"]])
    }
  }
}

# This policy grants permissions to access the specified ECR repositories
resource "aws_iam_role" "this" {
  name               = var.role_name
  assume_role_policy = data.aws_iam_policy_document.github_assume_role.json
}

resource "aws_iam_role_policy_attachment" "custom_policies" {
  count      = length(var.custom_policy_arns)
  role       = aws_iam_role.this.name
  policy_arn = var.custom_policy_arns[count.index]
}