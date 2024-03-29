locals {
  docker_mlflow_sagemaker_base_image = var.docker_mlflow_sagemaker_base_image
  base_image_tag                     = split(":", var.docker_mlflow_sagemaker_base_image)[1]
  ecr_repository_name                = "mlflow-sagemaker-deployment"
  iam_name_sagemaker_access          = "sagemaker-access"

  sagemaker_dashboard_read_access_user_name = "sagemaker-dashboard-read-access-user"
  sagemaker_dashboard_read_access_role_name = "sagemaker-dashboard-read-access-role"
  sagemaker_dashboard_read_access_secret    = "sagemaker-dashboard-read-access-secret"
}

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}
data "aws_iam_policy" "AmazonSageMakerFullAccess" {
  arn = "arn:aws:iam::aws:policy/AmazonSageMakerFullAccess"
}
data "aws_iam_policy" "AmazonSageMakerReadOnlyAccess" {
  arn = "arn:aws:iam::aws:policy/AmazonSageMakerReadOnly"
}

# Create Container Registry
module "ecr" {
  source          = "terraform-aws-modules/ecr/aws"
  repository_name = local.ecr_repository_name

  repository_lifecycle_policy = jsonencode({
    rules = [
      {
        rulePriority = 1,
        description  = "Keep last 30 images",
        selection = {
          tagStatus     = "tagged",
          tagPrefixList = ["v"],
          countType     = "imageCountMoreThan",
          countNumber   = 30
        },
        action = {
          type = "expire"
        }
      }
    ]
  })
  repository_force_delete = true
  # tags = {
  #   Terraform   = "true"
  #   Environment = "dev"
  # }
}

# mlflow sagemaker build-and-push-container --build --no-push -c mlflow-sagemaker-deployment
# https://mlflow.org/docs/latest/cli.html
resource "null_resource" "docker_packaging" {
  provisioner "local-exec" {
    command = <<EOF
	    docker pull "${local.docker_mlflow_sagemaker_base_image}"
      docker tag "${local.docker_mlflow_sagemaker_base_image}" "${module.ecr.repository_url}:${local.base_image_tag}"
      aws ecr get-login-password --region ${data.aws_region.current.name} | docker login --username AWS --password-stdin ${data.aws_caller_identity.current.account_id}.dkr.ecr.${data.aws_region.current.name}.amazonaws.com
	    docker push "${module.ecr.repository_url}:${local.base_image_tag}"
	    EOF
  }

  # triggers = {
  #   "run_at" = timestamp()
  # }
  depends_on = [
    module.ecr,
  ]
}

# Access role to allow access to Sagemaker
resource "aws_iam_role" "sagemaker_access_role" {
  name                 = "${local.iam_name_sagemaker_access}-role"
  max_session_duration = 28800

  assume_role_policy = <<EOF
  {
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "",
            "Effect": "Allow",
            "Principal": {
                "Service": "sagemaker.amazonaws.com"
            },
            "Action": "sts:AssumeRole"
        }
    ]
  }
  EOF
  # tags = {
  #   tag-key = "tag-value"
  # }
}

resource "aws_iam_role_policy_attachment" "sagemaker_access_role_policy" {
  role       = aws_iam_role.sagemaker_access_role.name
  policy_arn = data.aws_iam_policy.AmazonSageMakerFullAccess.arn
}

# Helm Deployment
resource "helm_release" "sagemaker-dashboard" {
  name             = var.name
  namespace        = var.namespace
  create_namespace = var.create_namespace

  chart = "${path.module}/helm/"
  values = [yamlencode({
    deployment = {
      image     = "seblum/streamlit-sagemaker-app:v1.0.0",
      name      = "sagemaker-streamlit",
      namespace = "${var.namespace}"
    },
    ingress = {
      host = "${var.domain_name}"
      path = "${var.domain_suffix}"
    },
    secret = {
      aws_region            = "${data.aws_region.current.name}"
      aws_access_key_id     = "${aws_iam_access_key.sagemaker_dashboard_read_access_user_credentials.id}"
      aws_secret_access_key = "${aws_iam_access_key.sagemaker_dashboard_read_access_user_credentials.secret}"
      aws_role_name         = "${aws_iam_role.sagemaker_dashboard_read_access_role.name}"
    }
  })]
}

# Access role to allow access to Sagemaker
resource "aws_iam_role" "sagemaker_dashboard_read_access_role" {
  name                 = local.sagemaker_dashboard_read_access_role_name
  max_session_duration = 28800

  assume_role_policy = <<EOF
  {
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": {
              "AWS": "arn:aws:iam::${data.aws_caller_identity.current.account_id}:user/${aws_iam_user.sagemaker_dashboard_read_access_user.name}"
            },
            "Action": "sts:AssumeRole"
        }
    ]
  }
  EOF
  # tags = {
  #   tag-key = "tag-value"
  # }
}

resource "aws_iam_role_policy_attachment" "sagemaker_dashboard_read__access_role_policy" {
  role       = aws_iam_role.sagemaker_dashboard_read_access_role.name
  policy_arn = data.aws_iam_policy.AmazonSageMakerReadOnlyAccess.arn
}

resource "aws_iam_user" "sagemaker_dashboard_read_access_user" {
  name = local.sagemaker_dashboard_read_access_user_name
  path = "/"
}

resource "aws_iam_access_key" "sagemaker_dashboard_read_access_user_credentials" {
  user = aws_iam_user.sagemaker_dashboard_read_access_user.name
}
