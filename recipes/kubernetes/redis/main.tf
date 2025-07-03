terraform {
  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">= 2.0"
    }
  }
}

variable "context" {
  description = "This variable contains Radius recipe context."
  type = any
}

variable "port" {
  description = "The port Redis is offered on. Defaults to 6379."
  type = number
  default = 6379
}

resource "kubernetes_deployment" "redis" {
  metadata {
    name = "redis-${sha512(var.context.resource.id)}"
    namespace = var.context.runtime.kubernetes.namespace
    labels = {
      app = "redis"
    }
  }
  spec {
    selector {
      match_labels = {
        app = "redis"
        resource = var.context.resource.name
      }
    }
    template {
      metadata {
        labels = {
          app = "redis"
          resource = var.context.resource.name
        }
      }
      spec {
        container {
          name  = "redis"
          image = "redis:6"
          port {
            container_port = 6379
          }
        }
      }
    }
  }
}

resource "kubernetes_service" "redis" {
  metadata {
    name = "redis-${sha512(var.context.resource.id)}"
    namespace = var.context.runtime.kubernetes.namespace
  }
  spec {
    type = "ClusterIP"
    selector = {
      app = "redis"
      resource = var.context.resource.name
    }
    port {
      port        = var.port
      target_port = "6379"
    }
  }
}

output "result" {
  value = {
    values = {
      host = "${kubernetes_service.redis.metadata[0].name}.${kubernetes_service.redis.metadata[0].namespace}.svc.cluster.local"
      port = kubernetes_service.redis.spec.port[0].port
      username = ""
    }
    secrets = {
      password = ""
    }
    // UCP resource IDs
    resources = [
        "/planes/kubernetes/local/namespaces/${kubernetes_service.redis.metadata[0].namespace}/providers/core/Service/${kubernetes_service.redis.metadata[0].name}",
        "/planes/kubernetes/local/namespaces/${kubernetes_deployment.redis.metadata[0].namespace}/providers/apps/Deployment/${kubernetes_deployment.redis.metadata[0].name}"
    ]
  }
  description = "The result of the Recipe. Must match the target resource's schema."
  sensitive = true
}