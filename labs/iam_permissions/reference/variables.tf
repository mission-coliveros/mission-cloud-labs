variable "resource_prefix" {
  type = string
}

variable "aws_account_id" {
  type = string
}

variable "aws_region" {
  type    = string
  default = "us-west-2"
}

variable "s3_uploader_roles" {
  default = ["MissionAdministrator"]
}

variable "s3_uploader_users" {
  default = []
}