locals {
  enabled_resources = {
    certificatesigningrequests      = ["certificates.k8s.io"]
    configmaps                      = [""]
    cronjobs                        = ["batch"]
    daemonsets                      = ["extensions", "apps"]
    deployments                     = ["extensions", "apps"]
    endpoints                       = [""]
    horizontalpodautoscalers        = ["autoscaling"]
    ingresses                       = ["extensions", "networking.k8s.io"]
    jobs                            = ["batch"]
    limitranges                     = [""]
    mutatingwebhookconfigurations   = ["admissionregistration.k8s.io"]
    namespaces                      = [""]
    networkpolicies                 = ["networking.k8s.io"]
    nodes                           = [""]
    persistentvolumeclaims          = [""]
    persistentvolumes               = [""]
    poddisruptionbudgets            = ["policy"]
    pods                            = [""]
    replicasets                     = ["extensions", "apps"]
    replicationcontrollers          = [""]
    resourcequotas                  = [""]
    secrets                         = [""]
    services                        = [""]
    statefulsets                    = ["apps"]
    storageclasses                  = ["storage.k8s.io"]
    validatingwebhookconfigurations = ["admissionregistration.k8s.io"]
    volumeattachments               = ["storage.k8s.io"]
  }
}

resource "kubernetes_cluster_role" "cluster_role" {
  metadata {
    name = var.service_name
  }
  dynamic "rule" {
    for_each = local.enabled_resources
    content {
      api_groups = rule.value
      resources  = [rule.key]
      verbs      = ["list", "watch"]
    }
  }
}

module "service_account" {
  source            = "../common/cluster-service-account"
  namespace_name    = var.namespace_name
  service_name      = var.service_name
  cluster_role_name = kubernetes_cluster_role.cluster_role.metadata[0].name
}

module "kube-state-metrics" {
  source         = "../common/stateless"
  cluster_domain = var.cluster_domain
  app_name       = var.service_name
  args = [
    "--port=${var.container_port}",
    "--resources=${join(",", keys(local.enabled_resources))}",
    "--telemetry-port=${var.container_metrics_port}"
  ]
  pod_resources = {
    cpu_min    = 50
    memory_min = 30
    memory_max = 30
  }
  namespace_name       = var.namespace_name
  service_account_name = module.service_account.name
  replicas             = 1
  container_image      = var.container_image
  ports = {
    http = {
      port        = var.service_port
      target_port = var.container_port
    }
    metrics = {
      target_port = var.container_metrics_port
    }
  }
  pod_security_context = {
    uid = 65534
  }
  pod_lifecycle = {
    min_readiness_time = 5
    max_readiness_time = 90
    max_cleanup_time   = 30
  }
  pod_probes = {
    port                   = var.container_port
    readiness_path         = "/"
    liveness_path          = "/healthz"
    readiness_polling_rate = 5
    liveness_polling_rate  = 5
  }
  stateless_node_labels = var.stateless_node_labels
}