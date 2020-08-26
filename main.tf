provider "aws" {
  alias = "dnsProvider"
}

provider "aws" {
  alias = "tools"
}

data "aws_caller_identity" "current" {}

locals {
  account_id   = data.aws_caller_identity.current.account_id
  secret_count = var.create_secrets ? 1 : 0
}

###################################################################
# S3 BUCKET
###################################################################

resource "aws_s3_bucket" "bucket" {
  acl           = "private"
  bucket        = var.bucket_name
  force_destroy = true

  tags = {
    Billing     = var.environment
    Environment = var.environment
    Name        = var.bucket_name
    Terraform   = "true"
  }

  website {
    error_document = "404.html"
    index_document = "index.html"
  }
}

###################################################################
# CLOUDFRONT
###################################################################

resource "aws_cloudfront_origin_access_identity" "origin_access_identity" {
  comment = "CloudFront Identity for ${var.app_name}"
}

module "cloudfront" {
  app_name               = var.app_name
  aws_region             = var.aws_region
  bucket_name            = aws_s3_bucket.bucket.id
  cloudfront_ttl         = var.cloudfront_ttl
  environment            = var.environment
  origin_access_identity = aws_cloudfront_origin_access_identity.origin_access_identity.cloudfront_access_identity_path
  source                  = "git::https://github.com/CharlesSieg/terraform-module-aws-cloudfront.git?ref=master"
}

data "aws_iam_policy_document" "policy_document" {
  statement {
    actions   = ["s3:*"]
    resources = ["${aws_s3_bucket.bucket.arn}/*"]

    principals {
      identifiers = ["arn:aws:iam::${local.account_id}:root"]
      type        = "AWS"
    }
  }

  statement {
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.bucket.arn}/*"]

    principals {
      identifiers = [aws_cloudfront_origin_access_identity.origin_access_identity.iam_arn]
      type        = "AWS"
    }
  }

  statement {
    actions   = ["s3:ListBucket"]
    resources = [aws_s3_bucket.bucket.arn]

    principals {
      identifiers = [aws_cloudfront_origin_access_identity.origin_access_identity.iam_arn]
      type        = "AWS"
    }
  }
}

// Create a bucket policy allowing the tools account to put objects into the bucket.
resource "aws_s3_bucket_policy" "bucket_policy" {
  bucket = aws_s3_bucket.bucket.id
  policy = data.aws_iam_policy_document.policy_document.json
}

###################################################################
# ROUTE 53: CREATE ENTRIES POINTING TO CLOUDFRONT DISTRIBUTION.
###################################################################

resource "aws_route53_record" "a" {
  allow_overwrite = true
  name            = aws_s3_bucket.bucket.id
  provider        = aws.dnsProvider
  type            = "A"
  zone_id         = var.domain_zone_id

  alias {
    evaluate_target_health = false
    name                   = module.cloudfront.domain_name
    zone_id                = module.cloudfront.hosted_zone_id
  }
}

resource "aws_route53_record" "aaaa" {
  allow_overwrite = true
  name            = aws_s3_bucket.bucket.id
  provider        = aws.dnsProvider
  type            = "AAAA"
  zone_id         = var.domain_zone_id

  alias {
    evaluate_target_health = false
    name                   = module.cloudfront.domain_name
    zone_id                = module.cloudfront.hosted_zone_id
  }
}

###################################################################
# CODEBUILD
###################################################################

data "aws_iam_role" "tools_codebuild_role" {
  name     = "codebuild-role"
  provider = aws.tools
}

resource "aws_codebuild_project" "main" {
  count         = local.secret_count
  build_timeout = "5"
  description   = "TBD"
  name          = "${var.environment}-${var.app_name}-website-build"
  provider      = aws.tools
  service_role  = data.aws_iam_role.tools_codebuild_role.arn

  artifacts {
    type = "NO_ARTIFACTS"
  }

  environment {
    compute_type                = "BUILD_GENERAL1_SMALL"
    image                       = "aws/codebuild/standard:2.0-1.13.0"
    image_pull_credentials_type = "CODEBUILD"
    privileged_mode             = true
    type                        = "LINUX_CONTAINER"

    environment_variable {
      name  = "AWS_REGION"
      value = var.aws_region
    }

    environment_variable {
      name  = "BUCKET_NAME"
      value = aws_s3_bucket.bucket.id
    }

    environment_variable {
      name  = "CDN_DISTRIBUTION_ID"
      value = module.cloudfront.distribution_id
    }

    environment_variable {
      name  = "TARGET_ACCOUNT_ID"
      value = local.account_id
    }
  }

  logs_config {
    cloudwatch_logs {
      group_name  = "codebuild"
      stream_name = "${var.environment}-${var.app_name}-website-build"
    }
  }

  source {
    git_clone_depth = 1
    location        = var.github_repo_url
    type            = "GITHUB"
  }

  tags = {
    Application = var.app_name
    Billing     = "${var.environment}-${var.app_name}"
    Environment = var.environment
    Name        = "${var.environment}-${var.app_name}-website-build"
    Terraform   = "true"
  }
}

#
# Github to CodeBuild webhook
#
resource "aws_codebuild_webhook" "main" {
  count        = local.secret_count
  project_name = aws_codebuild_project.main[count.index].name
  provider     = aws.tools

  filter_group {
    filter {
      pattern = "PUSH"
      type    = "EVENT"
    }

    filter {
      pattern = var.environment
      type    = "HEAD_REF"
    }
  }
}
