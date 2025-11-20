variable "kube_context" {
  type        = string
  description = "kubectl context name for the local Orbstack cluster"
  default     = "orbstack"
}

variable "teleport_proxy_addr" {
  description = "Teleport proxy address host:port"
  type        = string
}

variable "teleport_auth_token" {
  description = "Join token for teleport-kube-agent (kube,discovery)"
  type        = string
  sensitive   = true
}

variable "teleport_kube_cluster_name" {
  description = "Name under which the cluster appears in Teleport"
  type        = string
  default     = "orbstack-kube"
}
