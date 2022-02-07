locals {
  client_port             = 2379
  peer_port               = 2380
  data_volume_name        = "data"
  data_volume_mount_path  = "/var/run/etcd"
  data_volume_host_path   = "/etcd/data"
  service_client_endpoint = "${module.service.non_headless_service_hostname}:${local.client_port}"
  get_ip                  = "export IP=$(hostname -i)"
  member_hash_command     = "etcdctl member list | grep http://$${IP}:${local.peer_port} | cut -d':' -f1 | cut -d'[' -f1"
  get_peers_list          = <<-EOT
  PEERS=$(nslookup ${module.service.headless_service_hostname} 2>/dev/null | grep Address | awk -F ": " '{print $2}' | grep -v " ")
  EOT
  list_peers_function     = <<-EOT
  list_peers() {
    EPS=""
    for i in $${PEERS}; do
      EPS="$${EPS}$${EPS:+,}http://$${i}:${local.client_port}"
    done
    echo $${EPS}
  }
  EOT
  startup_script          = <<-EOT
  mkdir -p ${local.data_volume_mount_path}
  sleep 5
  HOSTNAME=$(hostname)
  ${local.get_ip}
  ${local.get_peers_list}
  echo "peers: $PEERS"
  ${local.list_peers_function}
  list_servers() {
    EPS=""
    for i in $${PEERS}; do
      EPS="$${EPS}$${EPS:+,}$${i}=http://$${i}:${local.peer_port}"
    done
    echo $${EPS},$${IP}=http://$${IP}:${local.peer_port}
  }
  collect_member() {
    ETCDCTL_ENDPOINT=$(list_peers)
    while ! etcdctl member list &>/dev/null; do sleep 1; done
    ${local.member_hash_command} > ${local.data_volume_mount_path}/member_id
    exit 0
  }
  member_hash() {
    ETCDCTL_ENDPOINT=$(list_peers) ${local.member_hash_command}
  }
  check_cluster() {
    ETCDCTL_ENDPOINT=$(list_peers) etcdctl member list > /dev/null
    local exit_code=$?
    echo "$exit_code"
  }
  if [ -e ${local.data_volume_mount_path}/default.etcd ]; then
    echo "rejoining cluster"
    member_id=$(cat ${local.data_volume_mount_path}/member_id)
    ETCDCTL_ENDPOINT=$(list_peers) etcdctl member update $${member_id} http://$${IP}:${local.peer_port}
    exec etcd --name $${IP} \
        --listen-peer-urls http://$${IP}:${local.peer_port} \
        --listen-client-urls http://$${IP}:${local.client_port},http://127.0.0.1:${local.client_port} \
        --advertise-client-urls http://$${IP}:${local.client_port} \
        --data-dir ${local.data_volume_mount_path}/default.etcd
  fi
  echo "checking for existing cluster"
  CLUSTER=$(check_cluster)
  if [[ "$CLUSTER" == "0" ]]; then
    echo "joining existing cluster"
    MEMBER_HASH=$(member_hash)
    echo "member hash is $MEMBER_HASH"
    if [ -n "$${MEMBER_HASH}" ]; then
        ETCDCTL_ENDPOINT=$(list_peers) etcdctl member remove $${MEMBER_HASH}
    fi
    ETCDCTL_ENDPOINT=$(list_peers) etcdctl member add $${IP} http://$${IP}:${local.peer_port} | grep "^ETCD_" > ${local.data_volume_mount_path}/new_member_envs
    if [ $? -ne 0 ]; then
      echo "exiting"
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
  fi
  echo "pinging peers"
  for i in $PEERS; do
    while true; do
      echo "waiting for $${i} to start..."
      ping -W 1 -c 1 $${i} > /dev/null && break
      sleep 1s
    done
  done
  collect_member &
  echo "joining new cluster"
  exec etcd --name $${IP} \
          --listen-peer-urls http://$${IP}:${local.peer_port} \
          --listen-client-urls http://$${IP}:${local.client_port},http://127.0.0.1:${local.client_port} \
          --advertise-client-urls http://$${IP}:${local.client_port} \
          --data-dir ${local.data_volume_mount_path}/default.etcd \
          --initial-advertise-peer-urls http://$${IP}:${local.peer_port} \
          --initial-cluster $(list_servers) \
          --initial-cluster-state new \
          --initial-cluster-token ${var.service_name}-cluster
  EOT
  pre_stop_script         = <<-EOT
  ${local.get_ip}
  ${local.get_peers_list}
  ${local.list_peers_function}
  echo "removing $${IP} from cluster"
  ETCDCTL_ENDPOINT=$(list_peers) etcdctl member remove $(${local.member_hash_command})
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

resource "kubernetes_daemonset" "daemonset" {
  metadata {
    name      = var.service_name
    namespace = var.namespace_name
  }
  spec {
    strategy {
      type = "RollingUpdate"
      rolling_update {
        max_unavailable = 1
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
        volume {
          name = local.data_volume_name
          empty_dir {
          }
        }
        container {
          name              = var.service_name
          image             = var.container_image
          image_pull_policy = "IfNotPresent"
          security_context {
            privileged = true
          }
          command = ["/bin/sh", "-ec", local.startup_script]
          lifecycle {
            pre_stop {
              exec {
                command = ["/bin/sh", "-ec", local.pre_stop_script]
              }
            }
          }
          resources {
            requests = {
              cpu : "75m"
              memory : "75Mi"
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
            initial_delay_seconds = 30
            period_seconds        = 15
            failure_threshold     = 4
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