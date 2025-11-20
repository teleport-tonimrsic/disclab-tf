variable "kube_context" {
  type = string
  description = "kubectl context name for the local Orbstack cluster"
  default = "orbstack"
}

provider "kubernetes" {
  config_path = "~/.kube/config"
  config_context = var.kube_context
}

provider "helm" {
  kubernetes {
    config_path = "~/.kube/config"
    config_context = var.kube_context
  }
}
