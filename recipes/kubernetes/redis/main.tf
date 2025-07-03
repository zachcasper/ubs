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

locals {
  uniqueName = var.context.resource.name
  namespace = var.context.runtime.kubernetes.namespace
}

resource "kubernetes_deployment" "postgresql" {
  metadata {
    name      = local.uniqueName
    namespace = local.namespace
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
          image = "redis"
          name  = "redis"
          port {
            container_port = 6379
          }
        }
      }
    }
  }
}

resource "kubernetes_service" "postgres" {
  metadata {
    name      = local.uniqueName
    namespace = local.namespace
  }

  spec {
    selector = {
      app = "redis"
      resource = var.context.resource.name
    }

    port {
      port = 6379
    } 
  }
}

output "result" {
  resources = [
    '/planes/kubernetes/local/namespaces/${svc.metadata.namespace}/providers/core/Service/${svc.metadata.name}'
    '/planes/kubernetes/local/namespaces/${redis.metadata.namespace}/providers/apps/Deployment/${redis.metadata.name}'
  ]
  value = {
    values = {
      host = "${kubernetes_service.redis.metadata[0].name}.${kubernetes_service.redis.metadata[0].namespace}.svc.cluster.local"
      port = 6379
    }
  }
}