variable "name_prefix" {

}

variable "name" {}

variable "namespace" {}


variable "create_namespace" {
  type        = bool
  description = "Should the namespace be created, if it does not exists?"
  default     = true
}

variable "s3_bucket_name" {
  type        = string
  description = "Name of the S3 Bucket for the MLFlow artifacts"
}

variable "s3_force_destroy" {
  type        = bool
  description = "Set to true to disable protection against s3 bucket being destroyed. Use only for dev!"
  default     = false
}

variable "oidc_provider_arn" {
  type        = string
  description = "arn of the OIDC provider"
}


# RDS

variable "vpc_id" {
  type        = string
  description = "VPC of the EKS cluster"
}

variable "private_subnets" {
  type        = list(string)
  description = "List of private subnets"
}

variable "private_subnets_cidr_blocks" {
  type        = list(string)
  description = "List of private subnet cidr blocks"
}

variable "rds_port" {
  type        = number
  description = "Port of the rds database"
}

variable "rds_name" {
  type        = string
  description = "Database name"
}

variable "rds_password" {
  type        = string
  description = "Database admin account password"
  default     = null
}

variable "rds_engine" {
  type        = string
  description = "The type of the database engine (postgres, mysql)"
}

variable "rds_engine_version" {
  type        = string
  description = "The engine version of the database"
}

variable "rds_instance_class" {
  type        = string
  description = "Database instance type"
}

variable "storage_type" {
  type        = string
  description = "Instance storage type: standard, gp2, gp3, or io1"
}

variable "max_allocated_storage" {
  type        = number
  description = "The upper limit of scalable storage (Gb)"
  default     = 500
}

variable "airflow_s3_role_name" {
  default = "airflow-s3-data-bucket-role"
}

variable "s3_data_bucket_user_name" {

}