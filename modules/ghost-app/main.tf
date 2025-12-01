variable "namespace" {
  type = string
  description = "Namespace to deploy Ghost into"
}

variable "labels" {
  type = map(string)
  description = "Base labels for Ghost"
  default = {
    app = "ghost"
    env = "lab"
  }
}

variable "ghost_hostname" {
  type = string
  description = "Public URL Ghost should think it's running on."
  default = "https://ghost-blog.ankh-morpork.teleport.sh"
}

locals {
  labels = var.labels
}

resource "kubernetes_deployment" "ghost" {
  metadata {
    name = "ghost"
    namespace = var.namespace
    labels = local.labels
  }

spec {
  replicas = 1

  selector {
    match_labels = local.labels
  }

  template {
    metadata {
      labels = local.labels
    }

    spec {
      container {
        name = "ghost"
        image = "ghost:latest"
      
        env {
          name = "url"
          value = var.ghost_hostname
        }

        env {
          name = "database__client"
          value = "sqlite3"
        }

        env {
          name = "database__connection__filename"
          value = "content/data/ghost.db"
        }

        env {
          name = "database__useNullAsDefault"
          value = "true"
        }

        port {
          container_port = 2368
          name = "http"
        }
      }
    }
  }
}
}


resource "kubernetes_service" "ghost" {
  metadata {
    name = "ghost"
    namespace = var.namespace
    labels = local.labels

    annotations = {
      "teleport.dev/name" = "ghost-blog"
      "teleport.dev/description" = "Ghost blog on orbstack lab"
      "teleport.dev/protocol" = "http"
      "teleport.dev/public-addr" = "ghost-blog.ankh-morpork.teleport.sh"
    }
  }

spec {
  selector = local.labels

  port {
    name = "http"
    port = 2368
    target_port = 2368
    protocol = "TCP"
  }
  type = "ClusterIP"
  }
}
