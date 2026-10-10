terraform {
  backend "s3" {
    bucket         = "khaipd18-obe-tf-state-445817183958"
    key            = "dev/terraform.tfstate"
    region         = "ap-southeast-1"
    encrypt        = true
    dynamodb_table = "khaipd18-devops-project-terraform-state-lock"
  }
}