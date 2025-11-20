locals {
  demo_namespace = "disclab"
}

resource "kubernetes_namespace" "demo" {
  metadata {
    name = local.demo_namespace
    labels = {
      "app" = "disclab"
      "env" = "local"
      "owner" = "toni.mrsic"
    }
  }
}
