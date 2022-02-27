locals {
  preemptible_node_label = var.preemptible_node_label_name != null && var.preemptible_node_label_value != null ? {
    (var.preemptible_node_label_name) = var.preemptible_node_label_value
  } : {}
}
locals {
  snapshot_count          = 1000
  client_port             = 2379
  cluster_domain          = "cluster.local"
  peer_port               = 2380
  data_volume_name        = "data"
  data_volume_mount_path  = "/var/run/etcd"
  service_client_endpoint = "${module.service.non_headless_service_hostname}:${local.client_port}"
  domain_suffix           = module.service.headless_service_name

  script_globals = <<-EOT
  SET_ID="$${POD_NAME##*-}"
  SET_NAME="$${POD_NAME%%-*}"
  HOSTNAME="$${POD_NAME}.${local.domain_suffix}"
  IP=$(hostname -i)
  ALL_CLIENT_ENDPOINTS=""
  for i in $(seq 0 $(($${SET_ID} - 1))); do
      ALL_CLIENT_ENDPOINTS="$${ALL_CLIENT_ENDPOINTS}$${ALL_CLIENT_ENDPOINTS:+,}http://$${SET_NAME}-$${i}.${local.domain_suffix}:${local.client_port}"
  done
  echo "SET_ID: $SET_ID"
  echo "SET_NAME: $SET_NAME"
  echo "HOSTNAME: $HOSTNAME"
  echo "IP: $IP"
  echo "ALL_CLIENT_ENDPOINTS: $ALL_CLIENT_ENDPOINTS"
  EOT

  startup_script = <<-EOT
  ${local.script_globals}
  if [ "$ALL_CLIENT_ENDPOINTS" != "" ]; then
      echo "existing cluster found"
      MEMBER_ID=$(etcdctl member list --endpoints="$ALL_CLIENT_ENDPOINTS" | grep http://$${HOSTNAME}:${local.peer_port} | cut -d',' -f1 | cut -d'[' -f1)
      if [ "$MEMBER_ID" != "" ]; then
          echo "existing membership found: $MEMBER_ID"
          if [ -e ${local.data_volume_mount_path}/default.etcd ]; then
              echo "existing local data found -- re-joining existing cluster using existing membership"
              etcdctl member update --endpoints="$ALL_CLIENT_ENDPOINTS" $MEMBER_ID --peer-urls=http://$${HOSTNAME}:${local.peer_port}
              exec etcd --name $${POD_NAME} --data-dir ${local.data_volume_mount_path}/default.etcd --listen-peer-urls http://0.0.0.0:${local.peer_port} --listen-client-urls http://0.0.0.0:${local.client_port} \
                  --advertise-client-urls http://$${HOSTNAME}:${local.client_port},http://${local.service_client_endpoint} \
                  --snapshot-count=${local.snapshot_count}
          else
              echo "existing local data not found -- removing existing membership"
              etcdctl member remove --endpoints="$ALL_CLIENT_ENDPOINTS" $MEMBER_ID
          fi
      fi
      echo "creating new membership"
      etcdctl member add --endpoints="$ALL_CLIENT_ENDPOINTS" $${POD_NAME} --peer-urls=http://$${HOSTNAME}:${local.peer_port} | grep "^ETCD_" > ${local.data_volume_mount_path}/new_member_envs
      . ${local.data_volume_mount_path}/new_member_envs
      exec etcd --name $${POD_NAME} --data-dir ${local.data_volume_mount_path}/default.etcd --listen-peer-urls http://0.0.0.0:${local.peer_port} --listen-client-urls http://0.0.0.0:${local.client_port} \
          --advertise-client-urls http://$${HOSTNAME}:${local.client_port},http://${local.service_client_endpoint} \
          --initial-advertise-peer-urls http://$${HOSTNAME}:${local.peer_port} \
          --initial-cluster $${ETCD_INITIAL_CLUSTER} --initial-cluster-state $${ETCD_INITIAL_CLUSTER_STATE} \
          --snapshot-count=${local.snapshot_count}
  else
      echo "existing cluster not found -- founding new cluster"
      exec etcd --name $${POD_NAME} --data-dir ${local.data_volume_mount_path}/default.etcd --listen-peer-urls http://0.0.0.0:${local.peer_port} --listen-client-urls http://0.0.0.0:${local.client_port} \
          --advertise-client-urls http://$${HOSTNAME}:${local.client_port},http://${local.service_client_endpoint} \
          --initial-advertise-peer-urls http://$${HOSTNAME}:${local.peer_port} \
          --initial-cluster "$${POD_NAME}=http://$${HOSTNAME}:${local.peer_port}" --initial-cluster-state new --initial-cluster-token ${var.service_name}-cluster \
          --snapshot-count=${local.snapshot_count}
  fi
  EOT

  pre_stop_script = <<-EOT
  ${local.script_globals}
  MEMBER_ID=$(etcdctl member list | grep http://$${IP}:${local.peer_port} | cut -d',' -f1 | cut -d'[' -f1)
  echo "removing $${POD_NAME} from cluster"
  if [ "$ALL_CLIENT_ENDPOINTS" != "" ]; then
      etcdctl member remove --endpoints="$ALL_CLIENT_ENDPOINTS" $MEMBER_ID
  fi
  rm -rf ${local.data_volume_mount_path}/*
  EOT

}

module "service" {
  source         = "../common/service"
  namespace_name = var.namespace_name
  service_name   = var.service_name
  ports = {
    client = {
      port        = local.client_port
      target_port = local.client_port
    }
    peer = {
      port        = local.peer_port
      target_port = local.peer_port
    }
  }
  wait_for_readiness = false
}

resource "kubernetes_stateful_set" "stateful_set" {
  metadata {
    name      = var.service_name
    namespace = var.namespace_name
  }
  spec {
    service_name = module.service.headless_service_name
    replicas     = var.cluster_size
    update_strategy {
      rolling_update {
        partition = 0
      }
    }
    volume_claim_template {
      metadata {
        name      = local.data_volume_name
        namespace = var.namespace_name
      }
      spec {
        access_modes = ["ReadWriteOnce"]
        resources {
          requests = {
            storage = "200Mi"
          }
        }
      }
    }
    selector {
      match_labels = {
        component = var.service_name
      }
    }
    template {
      metadata {
        name = var.service_name
        labels = {
          component = var.service_name
        }
      }
      spec {
        affinity {
          dynamic "node_affinity" {
            for_each = { for k, v in local.preemptible_node_label : k => v }
            content {
              required_during_scheduling_ignored_during_execution {
                node_selector_term {
                  match_expressions {
                    key      = node_affinity.key
                    operator = "NotIn"
                    values   = [node_affinity.value]
                  }
                }
              }
            }
          }
          pod_anti_affinity {
            required_during_scheduling_ignored_during_execution {
              label_selector {
                match_labels = {
                  component = var.service_name
                }
              }
              topology_key = "kubernetes.io/hostname"
            }
            preferred_during_scheduling_ignored_during_execution {
              weight = 100
              pod_affinity_term {
                label_selector {
                  match_labels = {
                    component = var.service_name
                  }
                }
                topology_key = "topology.kubernetes.io/zone"
              }
            }
          }
        }
        container {
          name              = var.service_name
          image             = var.container_image
          image_pull_policy = "IfNotPresent"
          command           = ["/bin/sh", "-ec", local.startup_script]
          lifecycle {
            pre_stop {
              exec {
                command = ["/bin/sh", "-ec", local.pre_stop_script]
              }
            }
          }
          env {
            name = "POD_NAME"
            value_from {
              field_ref {
                field_path = "metadata.name"
              }
            }
          }
          resources {
            requests = {
              cpu : "50m"
              memory : "100Mi"
            }
            limits = {
              memory : "150Mi"
            }
          }
          readiness_probe {
            http_get {
              port = local.client_port
              path = "/health"
            }
            initial_delay_seconds = 15
            period_seconds        = 15
            failure_threshold     = 5
          }
          #          liveness_probe {
          #            http_get {
          #              port = local.client_port
          #              path = "/health"
          #            }
          #            initial_delay_seconds = 90
          #            period_seconds        = 15
          #          }
          port {
            protocol       = "TCP"
            container_port = local.client_port
          }
          port {
            protocol       = "TCP"
            container_port = local.peer_port
          }
          volume_mount {
            name       = local.data_volume_name
            mount_path = local.data_volume_mount_path
          }
        }
      }
    }
  }
}