resource "kubernetes_service" "etcd" {
  metadata {
    name      = "etcd"
    namespace = var.namespace_name
  }
  spec {
    type             = "ClusterIP"
    session_affinity = "None"
    port {
      port        = 2379
      target_port = "client"
    }
    port {
      port        = 2380
      target_port = "peer"
    }
    selector = {
      "component" = "etcd"
    }
  }
}
resource "kubernetes_service" "etcd_headless" {
  metadata {
    name      = "etcd-headless"
    namespace = var.namespace_name
    annotations = {
      "service.alpha.kubernetes.io/tolerate-unready-endpoints" = "true"
    }
  }
  spec {
    type                        = "ClusterIP"
    cluster_ip                  = "None"
    publish_not_ready_addresses = true
    port {
      port        = 2379
      target_port = "client"
    }
    port {
      port        = 2380
      target_port = "peer"
    }
    selector = {
      "component" = "etcd"
    }
  }
}
resource "kubernetes_stateful_set" "etcd" {
  metadata {
    name      = "etcd"
    namespace = var.namespace_name
    labels = {
      "component" = "etcd"
    }
  }
  spec {
    replicas              = 1
    service_name          = "etcd"
    pod_management_policy = "Parallel"
    update_strategy {
      type = "RollingUpdate"
    }
    selector {
      match_labels = {
        "component" = "etcd"
      }
    }
    template {
      metadata {
        name = "etcd"
        labels = {
          "component" = "etcd"
        }
      }
      spec {
        container {
          name              = "etcd"
          image             = "quay.io/coreos/etcd:latest"
          image_pull_policy = "IfNotPresent"
          command = [
            "etcd",
          ]
          args = [
            "--name ${"$"}{HOSTNAME}",
            "--listen-peer-urls http://0.0.0.0:2380",
            "--listen-client-urls http://0.0.0.0:2379",
            "--advertise-client-urls http://${"$"}{HOSTNAME}.etcd:2379",
            "--initial-advertise-peer-urls http://${"$"}{HOSTNAME}.etcd:2380",
            "--initial-cluster-token etcd-cluster-1",
            "--initial-cluster etcd-0=http://etcd-0.etcd:2380,etcd-1=http://etcd-1.etcd:2380,etcd-2=http://etcd-2.etcd:2380",
            "--initial-cluster-state new",
            "--data-dir /var/run/etcd/default.etcd",
          ]
          volume_mount {
            name       = "data"
            mount_path = "/var/run/etcd"
          }
          port {
            name           = "client"
            protocol       = "TCP"
            container_port = 2379
          }
          port {
            name           = "peer"
            protocol       = "TCP"
            container_port = 2380
          }
        }
      }
    }
    volume_claim_template {
      metadata {
        name = "data"
      }
      spec {
        storage_class_name = "ssd"
        access_modes       = ["ReadWriteOnce"]
        resources {
          requests = {
            storage = "1Gi"
          }
        }
      }
    }
  }
}