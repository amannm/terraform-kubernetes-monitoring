locals {
  client_port             = 2379
  cluster_domain          = "cluster.local"
  peer_port               = 2380
  data_volume_name        = "data"
  data_volume_mount_path  = "/var/run/etcd"
  service_client_endpoint = "${module.service.non_headless_service_hostname}:${local.client_port}"
  domain_suffix           = module.service.headless_service_name
  script_globals          = <<-EOT
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

  get_member_id = "etcdctl member list --endpoints=\"$ALL_CLIENT_ENDPOINTS\" | grep http://$${HOSTNAME}:${local.peer_port} | cut -d',' -f1 | cut -d'[' -f1"

  startup_script = <<-EOT
  ${local.script_globals}
  save_member_id() {
      MEMBER_ID=""
      while [ "$MEMBER_ID" == "" ]; do
        echo "waiting for member ID assignment..."
        sleep 1
        MEMBER_ID=$(${local.get_member_id})
      done
      echo "member ID generated -- saving to disk"
      ${local.get_member_id} > ${local.data_volume_mount_path}/member_id
      echo "member ID saved to disk"
      exit 0
  }
  if [ "$ALL_CLIENT_ENDPOINTS" != "" ]; then
      echo "existing cluster found"
      if [ -e ${local.data_volume_mount_path}/default.etcd ]; then
          echo "re-joining existing cluster as existing member"
          etcdctl member update --endpoints="$ALL_CLIENT_ENDPOINTS" $(cat ${local.data_volume_mount_path}/member_id) --peer-urls=http://$${HOSTNAME}:${local.peer_port}
          exec etcd --name $${POD_NAME} \
              --listen-peer-urls http://$${IP}:${local.peer_port} \
              --listen-client-urls http://$${IP}:${local.client_port},http://127.0.0.1:${local.client_port} \
              --advertise-client-urls http://$${HOSTNAME}:${local.client_port} \
              --data-dir ${local.data_volume_mount_path}/default.etcd
      else
          MEMBER_ID=$(${local.get_member_id})
          if [ -n "$${MEMBER_ID}" ]; then
              echo "clearing previous membership from existing cluster"
              etcdctl member remove --endpoints="$ALL_CLIENT_ENDPOINTS" $${MEMBER_ID}
          fi
          echo "registering with existing cluster as new member"
          etcdctl member add --endpoints="$ALL_CLIENT_ENDPOINTS" $${POD_NAME} --peer-urls=http://$${HOSTNAME}:${local.peer_port} | grep "^ETCD_" > ${local.data_volume_mount_path}/new_member_envs
          if [ $? -ne 0 ]; then
              echo "failed to register with existing cluster"
              rm -f ${local.data_volume_mount_path}/new_member_envs
              exit 1
          fi
          cat ${local.data_volume_mount_path}/new_member_envs
          source ${local.data_volume_mount_path}/new_member_envs
          save_member_id &
          echo "joining existing cluster"
          exec etcd --name $${POD_NAME} \
              --listen-peer-urls http://$${IP}:${local.peer_port} \
              --listen-client-urls http://$${IP}:${local.client_port},http://127.0.0.1:${local.client_port} \
              --advertise-client-urls http://$${HOSTNAME}:${local.client_port} \
              --data-dir ${local.data_volume_mount_path}/default.etcd \
              --initial-advertise-peer-urls http://$${HOSTNAME}:${local.peer_port} \
              --initial-cluster $${ETCD_INITIAL_CLUSTER} \
              --initial-cluster-state $${ETCD_INITIAL_CLUSTER_STATE}
      fi
  else
      echo "existing cluster not found"
      save_member_id &
      echo "founding new cluster"
      exec etcd --name $${POD_NAME} \
          --listen-peer-urls http://$${IP}:${local.peer_port} \
          --listen-client-urls http://$${IP}:${local.client_port},http://127.0.0.1:${local.client_port} \
          --advertise-client-urls http://$${HOSTNAME}:${local.client_port} \
          --data-dir ${local.data_volume_mount_path}/default.etcd \
          --initial-advertise-peer-urls http://$${HOSTNAME}:${local.peer_port} \
          --initial-cluster "$${POD_NAME}=http://$${HOSTNAME}:${local.peer_port}" \
          --initial-cluster-state new \
          --initial-cluster-token ${var.service_name}-cluster
  fi
  EOT

  pre_stop_script = <<-EOT
  ${local.script_globals}
  MEMBER_ID=$(${local.get_member_id})
  echo "removing $${POD_NAME} from cluster"
  etcdctl member remove --endpoints="$ALL_CLIENT_ENDPOINTS" $(${local.get_member_id})
  if [ $? -eq 0 ]; then
      rm -rf ${local.data_volume_mount_path}/*
  fi
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
                topology_key = "failure-domain.beta.kubernetes.io/zone"
              }
            }
          }
        }
        container {
          name              = var.service_name
          image             = var.container_image
          image_pull_policy = "IfNotPresent"
          command           = ["/bin/sh", "-c", local.startup_script]
          lifecycle {
            pre_stop {
              exec {
                command = ["/bin/sh", "-c", local.pre_stop_script]
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
              cpu : "100m"
              memory : "125Mi"
            }
            limits = {
              memory : "300Mi"
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
          liveness_probe {
            http_get {
              port = local.client_port
              path = "/health"
            }
            initial_delay_seconds = 90
            period_seconds        = 15
          }
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