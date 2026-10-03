resource "aws_ecr_repository" "ecr_repository" {
  for_each             = var.repository_names
  name                 = each.value
  image_tag_mutability = var.image_tag_mutability
  force_delete         = var.force_delete
}

# Scanning is configured at the registry level, as recommended by AWS: the repository-level
# image_scanning_configuration (PutImageScanningConfiguration API) is being deprecated.
# Note: this resource owns the scanning configuration of the whole private registry in this region.
resource "aws_ecr_registry_scanning_configuration" "this" {
  scan_type = "BASIC"

  dynamic "rule" {
    for_each = var.scan_on_push ? [1] : []
    content {
      scan_frequency = "SCAN_ON_PUSH"

      dynamic "repository_filter" {
        for_each = var.repository_names
        content {
          filter      = repository_filter.value
          filter_type = "WILDCARD"
        }
      }
    }
  }
}

resource "aws_ecr_repository_policy" "this" {
  for_each   = (length(var.allow_push_principals) + length(var.allow_pull_principals)) > 0 ? aws_ecr_repository.ecr_repository : {}
  repository = each.value.name
  policy     = data.aws_iam_policy_document.repository_policy.json
}

resource "aws_ecr_lifecycle_policy" "this" {
  for_each = aws_ecr_repository.ecr_repository

  repository = each.value.name

  policy = <<EOF
{
  "rules": [
    {
      "rulePriority": 1,
      "description": "Expire untagged images older than 14 days",
      "selection": {
        "tagStatus": "untagged",
        "countType": "sinceImagePushed",
        "countUnit": "days",
        "countNumber": 14
      },
      "action": {
        "type": "expire"
      }
    },
    {
      "rulePriority": 2,
      "description": "Archive images not pulled in 90 days",
      "selection": {
        "tagStatus": "any",
        "countType": "sinceImagePulled",
        "countUnit": "days",
        "countNumber": 90
      },
      "action": {
        "type": "transition",
        "targetStorageClass": "archive"
      }
    },
    {
      "rulePriority": 3,
      "description": "Delete images archived for more than 365 days",
      "selection": {
        "tagStatus": "any",
        "storageClass": "archive",
        "countType": "sinceImageTransitioned",
        "countUnit": "days",
        "countNumber": 365
      },
      "action": {
        "type": "expire"
      }
    }
  ]
}
EOF
}