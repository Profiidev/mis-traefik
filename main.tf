terraform {
  required_version = "~> 1.12"

  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.0"
    }
    kubectl = {
      source  = "gavinbunney/kubectl"
      version = "~> 1.0"
    }
    external = {
      source  = "hashicorp/external"
      version = "~> 2.0"
    }
  }
}

provider "kubernetes" {
  config_path    = "${path.module}/kubeconfig"
  config_context = "minikube" # Changed from default
}

provider "helm" {
  kubernetes {
    config_path    = "${path.module}/kubeconfig"
    config_context = "minikube" # Changed from default
  }
}

provider "kubectl" {
  config_path    = "${path.module}/kubeconfig"
  config_context = "minikube" # Changed from default
}

resource "kubernetes_namespace" "traefik" {
  metadata {
    name = "traefik"
  }
}

resource "helm_release" "traefik" {
  name       = "traefik"
  repository = "https://traefik.github.io/charts"
  chart      = "traefik"
  version    = "40.2.0"
  namespace  = "traefik"

  values = [<<YAML
experimental:
  fastProxy:
    enabled: true

providers:
  kubernetesCRD:
    allowCrossNamespace: true
    allowExternalNameServices: true
  kubernetesIngressNGINX:
    ingressClass: traefik
    controllerClass: "k8s.io/ingress-nginx"
    watchIngressWithoutClass: false
    ingressClassByName: false
service:
  spec:
    type: ClusterIP
ingressRoute:
  dashboard:
    enabled: true
    matchRule: "Host(`dashboard.localhost`)"
    entryPoints:
      - web
YAML
  ]

  depends_on = [kubernetes_namespace.traefik]
}

resource "kubernetes_deployment" "whoami" {
  metadata {
    name      = "whoami"
    namespace = kubernetes_namespace.traefik.metadata[0].name
    labels = {
      app = "whoami"
    }
  }

  spec {
    replicas = 2

    selector {
      match_labels = {
        app = "whoami"
      }
    }

    template {
      metadata {
        labels = {
          app = "whoami"
        }
      }

      spec {
        container {
          image = "traefik/whoami:v1.10"
          name  = "whoami"

          port {
            container_port = 80
            name           = "http"
          }
        }
      }
    }
  }
}

resource "kubernetes_service" "whoami" {
  metadata {
    name      = "whoami"
    namespace = kubernetes_namespace.traefik.metadata[0].name
  }

  spec {
    selector = {
      app = kubernetes_deployment.whoami.metadata[0].labels.app
    }

    port {
      port        = 80
      target_port = "http"
    }

    type = "ClusterIP"
  }
}

resource "kubernetes_ingress_v1" "whoami_ingress" {
  metadata {
    name      = "whoami-ingress"
    namespace = kubernetes_namespace.traefik.metadata[0].name
  }

  spec {
    ingress_class_name = "traefik"

    rule {
      host = "app.localhost"

      http {
        path {
          path      = "/"
          path_type = "Prefix"

          backend {
            service {
              name = kubernetes_service.whoami.metadata[0].name
              port {
                number = 80
              }
            }
          }
        }
      }
    }
  }

  depends_on = [helm_release.traefik]
}
