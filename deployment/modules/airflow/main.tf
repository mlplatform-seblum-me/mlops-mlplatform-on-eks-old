locals {
  k8s_airflow_db_secret_name   = "${var.name_prefix}-${var.namespace}-db-auth"
  git_airflow_repo_secret_name = "${var.name_prefix}-${var.namespace}-https-git-secret"
  s3_data_bucket_secret_name   = "${var.name_prefix}-${var.namespace}-${var.s3_data_bucket_secret_name}"
  s3_data_bucket_name          = "${var.name_prefix}-${var.namespace}-${var.s3_data_bucket_name}"
  s3_log_bucket_name           = "${var.name_prefix}-${var.namespace}-log-storage"
}



data "aws_caller_identity" "current" {}
data "aws_region" "current" {} # 

resource "kubernetes_namespace" "airflow" {
  metadata {

    name = var.namespace
  }
}

####### LOG STORAGE

module "s3-remote-logging" {
  source             = "./remote_logging"
  s3_log_bucket_name = local.s3_log_bucket_name
  namespace          = var.namespace
  s3_force_destroy   = var.s3_force_destroy
  oidc_provider_arn  = var.oidc_provider_arn
}


####### DATA STORAGE

module "s3-data-storage" {
  source                     = "./data_storage"
  s3_data_bucket_name        = local.s3_data_bucket_name
  namespace                  = var.namespace
  s3_force_destroy           = var.s3_force_destroy
  s3_data_bucket_secret_name = local.s3_data_bucket_secret_name
}


# HELM

resource "kubernetes_secret" "airflow_db_credentials" {
  metadata {
    name      = local.k8s_airflow_db_secret_name
    namespace = helm_release.airflow.namespace
  }
  data = {
    "postgresql-password" = module.rds-airflow.rds_password
  }
}

resource "kubernetes_secret" "airflow_https_git_secret" {
  metadata {
    name      = local.git_airflow_repo_secret_name
    namespace = helm_release.airflow.namespace
  }
  data = {
    "username" = var.git_username
    "password" = var.git_token
  }
}

resource "random_password" "rds_password" {
  length  = 16
  special = false
}


# create rds for airflow
module "rds-airflow" {
  source                      = "../../infrastructure/rds"
  vpc_id                      = var.vpc_id
  private_subnets             = var.private_subnets
  private_subnets_cidr_blocks = var.private_subnets_cidr_blocks
  rds_port                    = var.rds_port
  rds_name                    = var.rds_name
  rds_password                = coalesce(var.rds_password, random_password.rds_password.result)
  rds_engine                  = var.rds_engine
  rds_engine_version          = var.rds_engine_version
  rds_instance_class          = var.rds_instance_class
  storage_type                = var.storage_type
  max_allocated_storage       = var.max_allocated_storage
}


resource "helm_release" "airflow" {
  name             = var.name
  namespace        = var.namespace
  create_namespace = var.create_namespace

  repository = "https://airflow-helm.github.io/charts"
  chart      = var.helm_chart_name
  version    = var.helm_chart_version
  wait       = false # deactivate post install hooks otherwise will fail

  values = [yamlencode({
    airflow = {
      config = {
        AIRFLOW__WEBSERVER__EXPOSE_CONFIG = true
        AIRFLOW__CORE__LOAD_EXAMPLES      = false
        # AIRFLOW__LOGGING__LOGGING_LEVEL          = "DEBUG"
        # AIRFLOW__LOGGING__REMOTE_LOGGING         = true
        # AIRFLOW__LOGGING__REMOTE_BASE_LOG_FOLDER = "s3://${module.s3-data-storage.s3_log_bucket_name}/airflow/logs"
        # AIRFLOW__LOGGING__REMOTE_LOG_CONN_ID     = "aws_logs_storage_access"
        AIRFLOW__CORE__DEFAULT_TIMEZONE = "Europe/Amsterdam"
      },
      users = var.user_profiles,
      image = {
        repository = "seblum/airflow"
        tag        = "2.6.3-python3.11-custom-light"
        pullPolicy = "IfNotPresent"
        pullSecret = ""
        uid        = 50000
        gid        = 0
      },
      executor           = "KubernetesExecutor"
      fernetKey          = "7T512UXSSmBOkpWimFHIVb8jK6lfmSAvx4mO6Arehnc="
      webserverSecretKey = "THIS IS UNSAFE!"
      connections = [
        {
          id          = "aws_logs_storage_access"
          type        = "aws"
          description = "AWS connection to store logs on S3"
          extra       = "{\"region_name\": \"eu-central-1\"}"
        }
      ],
      variables = [
        {
          key   = "MLFLOW_TRACKING_URI"
          value = "http://mlflow-service.mlflow.svc.cluster.local"
        },
        {
          key   = "s3_access_name"
          value = "${local.s3_data_bucket_secret_name}"
        }
      ]
    },
    serviceAccount = {
      create = true
      name   = "airflow-sa"
      annotations = {
        "eks.amazonaws.com/role-arn" = "${module.s3-remote-logging.s3_log_bucket_role_arn}"
      }
    },
    scheduler = {
      logCleanup = {
        enabled = false
      }
    },
    workers = {
      enabled = false
      logCleanup = {
        enables = true
      }
    },
    flower = {
      enabled = false
    },
    postgresql = {
      enabled = false
    },
    redis = {
      enabled = false
    },
    externalDatabase = {
      type              = "postgres"
      host              = module.rds-airflow.rds_host
      port              = var.rds_port
      database          = "airflow_db"
      user              = "airflow_admin"
      passwordSecret    = local.k8s_airflow_db_secret_name
      passwordSecretKey = "postgresql-password"
    },
    dags = {
      path = "/opt/airflow/dags"
      gitSync = {
        enabled               = true
        repo                  = var.git_repository_url
        branch                = var.git_branch
        revision              = "HEAD"
        repoSubPath           = "workflows"
        httpSecret            = local.git_airflow_repo_secret_name
        httpSecretUsernameKey = "username"
        httpSecretPasswordKey = "password"
        syncWait              = 60
        syncTimeout           = 120
      }
    },
    logs = {
      path = "/opt/airflow/logs"
      persistence = {
        enabled = true
        storageClass : "efs"
        size : "5Gi"
        accessMode : "ReadWriteMany"
      }
    },
  })]
}
