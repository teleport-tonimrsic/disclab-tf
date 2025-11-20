locals {
  demo_namespace = "disclab"
}

resource "kubernetes_namespace" "demo" {
  metadata {
    name = local.demo_namespace
    labels = {
      "app"   = "disclab"
      "env"   = "local"
      "owner" = "toni.mrsic"
    }
  }
}

resource "helm_release" "teleport_kube_agent" {
  name             = "teleport-kube-agent"
  namespace        = kubernetes_namespace.demo.metadata[0].name
  repository       = "https://charts.releases.teleport.dev"
  chart            = "teleport-kube-agent"
  version          = "18.4.0"
  create_namespace = false

  set = [
    {
      name  = "proxyAddr"
      value = var.teleport_proxy_addr
    },

    {
      name  = "authToken"
      value = var.teleport_auth_token
    },

    {
      name  = "kubeClusterName"
      value = var.teleport_kube_cluster_name
    },

    {
      name  = "roles"
      value = "kube\\,discovery"
    },

    {
      name  = "enterprise"
      value = "true"
    },

    {
      name  = "labels.env"
      value = "lab"
    },

    {
      name  = "labels.provider"
      value = "local"
    },
  ]
}
