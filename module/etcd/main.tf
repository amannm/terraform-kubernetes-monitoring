locals {
  cluster_size            = 3
  client_port             = 2379
  cluster_domain          = "cluster.local"
  peer_port               = 2380
  data_volume_name        = "data"
  data_volume_mount_path  = "/var/run/etcd"
  service_client_endpoint = "${module.service.non_headless_service_hostname}:${local.client_port}"

  script_globals = <<-EOT
  sleep 5
  PEER_IPS=$(nslookup ${module.service.headless_service_hostname} 2>/dev/null | grep Address | awk -F ": " '{print $2}' | grep -v " ")
  echo "peer IPs: $PEER_IPS"
  ALL_CLIENT_ENDPOINTS=""
  for peer_ip in $${PEER_IPS}; do
      ALL_CLIENT_ENDPOINTS="$${ALL_CLIENT_ENDPOINTS}$${ALL_CLIENT_ENDPOINTS:+,}http://$${peer_ip}:${local.client_port}"
  done
  echo "client endpoints: $ALL_CLIENT_ENDPOINTS"
  IP=$(hostname -i)
  echo "IP: $IP"
  EOT

  get_member_id = "etcdctl member list | grep http://$${IP}:${local.peer_port} | cut -d':' -f1 | cut -d'[' -f1"

  startup_script = <<-EOT
  ${local.script_globals}

  if [ -e ${local.data_volume_mount_path}/default.etcd ]; then
      echo "re-joining etcd cluster as existing member"
      ETCDCTL_ENDPOINT=$$ALL_CLIENT_ENDPOINTS etcdctl member update $(cat ${local.data_volume_mount_path}/member_id) http://$${IP}:${local.peer_port}
      exec etcd --name $${IP} \
          --listen-peer-urls http://$${IP}:${local.peer_port} \
          --listen-client-urls http://$${IP}:${local.client_port},http://127.0.0.1:${local.client_port} \
          --advertise-client-urls http://$${IP}:${local.client_port} \
          --data-dir ${local.data_volume_mount_path}/default.etcd
  fi

  collect_member() {
      while ! etcdctl member list &>/dev/null; do sleep 1; done
      ${local.get_member_id} > ${local.data_volume_mount_path}/member_id
      exit 0
  }

  check_cluster() {
      ETCDCTL_ENDPOINT=$$ALL_CLIENT_ENDPOINTS etcdctl member list > /dev/null
      local exit_code=$?
      echo "$exit_code"
  }

  CLUSTER=$(check_cluster)
  if [[ "$CLUSTER" == "0" ]]; then

      MEMBER_HASH=$(${local.get_member_id})
      if [ -n "$${MEMBER_HASH}" ]; then
          ETCDCTL_ENDPOINT=$$ALL_CLIENT_ENDPOINTS etcdctl member remove $${MEMBER_HASH}
      fi

      echo "adding new member"
      ETCDCTL_ENDPOINT=$$ALL_CLIENT_ENDPOINTS etcdctl member add $${IP} http://$${IP}:${local.peer_port} | grep "^ETCD_" > ${local.data_volume_mount_path}/new_member_envs
      if [ $? -ne 0 ]; then
          echo "Exiting"
          rm -f ${local.data_volume_mount_path}/new_member_envs
          exit 1
      fi
      cat ${local.data_volume_mount_path}/new_member_envs
      source ${local.data_volume_mount_path}/new_member_envs

      collect_member &

      exec etcd --name $${IP} \
          --listen-peer-urls http://$${IP}:${local.peer_port} \
          --listen-client-urls http://$${IP}:${local.client_port},http://127.0.0.1:${local.client_port} \
          --advertise-client-urls http://$${IP}:${local.client_port} \
          --data-dir ${local.data_volume_mount_path}/default.etcd \
          --initial-advertise-peer-urls http://$${IP}:${local.peer_port} \
          --initial-cluster $${ETCD_INITIAL_CLUSTER} \
          --initial-cluster-state $${ETCD_INITIAL_CLUSTER_STATE}

      tail -f /dev/null
  fi

  ALL_PEER_ENDPOINTS="$${IP}=http://$${IP}:${local.peer_port}"
  for peer_ip in $${PEER_IPS}; do
      ALL_PEER_ENDPOINTS="$${ALL_PEER_ENDPOINTS}$${ALL_PEER_ENDPOINTS:+,}$${peer_ip}=http://$${peer_ip}:${local.peer_port}"
  done

  collect_member &

  echo "founding new cluster"
  exec etcd --name $${IP} \
      --listen-peer-urls http://$${IP}:${local.peer_port} \
      --listen-client-urls http://$${IP}:${local.client_port},http://127.0.0.1:${local.client_port} \
      --advertise-client-urls http://$${IP}:${local.client_port} \
      --data-dir ${local.data_volume_mount_path}/default.etcd \
      --initial-advertise-peer-urls http://$${IP}:${local.peer_port} \
      --initial-cluster $${ALL_PEER_ENDPOINTS} \
      --initial-cluster-state new \
      --initial-cluster-token ${var.service_name}-cluster

  tail -f /dev/null

  EOT

  pre_stop_script = <<-EOT
  ${local.script_globals}

  echo "Removing $${IP} from etcd cluster"
  ETCDCTL_ENDPOINT=$$ALL_CLIENT_ENDPOINTS etcdctl member remove $(${local.get_member_id})
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
    service_name = var.service_name
    replicas     = local.cluster_size
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
          resources {
            requests = {
              cpu : "100m"
              memory : "125Mi"
            }
            limits = {
              memory : "200Mi"
            }
          }
          #          readiness_probe {
          #            http_get {
          #              port = local.client_port
          #              path = "/health"
          #            }
          #            initial_delay_seconds = 30
          #            period_seconds        = 15
          #            failure_threshold     = 4
          #          }
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