terraform {
  backend "s3" {
    bucket         = "terraform-tfstate-435037139863"
    key            = "kubernetes.aws.billeci.com"
    region         = "us-west-2"
    lock_table     = "terraform_locks"
  }
}
