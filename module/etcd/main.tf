locals {
  pod_name_env_var        = "POD_NAME"
  snapshot_count          = 1000
  peer_port               = var.service_port + 1
  data_volume_name        = "data"
  data_volume_mount_path  = "/var/run/etcd"
  service_client_endpoint = "${module.etcd.hostname}:${var.service_port}"
  domain_suffix           = "${var.service_name}-headless"

  script_globals = <<-EOT
  SET_ID="$${${local.pod_name_env_var}##*-}"
  SET_NAME="$${${local.pod_name_env_var}%%-*}"
  HOSTNAME="$${${local.pod_name_env_var}}.${local.domain_suffix}"
  IP=$(hostname -i)
  ALL_CLIENT_ENDPOINTS=""
  for i in $(seq 0 $(($${SET_ID} - 1))); do
      ALL_CLIENT_ENDPOINTS="$${ALL_CLIENT_ENDPOINTS}$${ALL_CLIENT_ENDPOINTS:+,}http://$${SET_NAME}-$${i}.${local.domain_suffix}:${var.service_port}"
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
              exec etcd --name $${${local.pod_name_env_var}} --data-dir ${local.data_volume_mount_path}/default.etcd --listen-peer-urls http://0.0.0.0:${local.peer_port} --listen-client-urls http://0.0.0.0:${var.service_port} \
                  --advertise-client-urls http://$${HOSTNAME}:${var.service_port},http://${local.service_client_endpoint} \
                  --snapshot-count=${local.snapshot_count}
          else
              echo "existing local data not found -- removing existing membership"
              etcdctl member remove --endpoints="$ALL_CLIENT_ENDPOINTS" $MEMBER_ID
          fi
      fi
      echo "creating new membership"
      etcdctl member add --endpoints="$ALL_CLIENT_ENDPOINTS" $${${local.pod_name_env_var}} --peer-urls=http://$${HOSTNAME}:${local.peer_port} | grep "^ETCD_" > ${local.data_volume_mount_path}/new_member_envs
      . ${local.data_volume_mount_path}/new_member_envs
      exec etcd --name $${${local.pod_name_env_var}} --data-dir ${local.data_volume_mount_path}/default.etcd --listen-peer-urls http://0.0.0.0:${local.peer_port} --listen-client-urls http://0.0.0.0:${var.service_port} \
          --advertise-client-urls http://$${HOSTNAME}:${var.service_port},http://${local.service_client_endpoint} \
          --initial-advertise-peer-urls http://$${HOSTNAME}:${local.peer_port} \
          --initial-cluster $${ETCD_INITIAL_CLUSTER} --initial-cluster-state $${ETCD_INITIAL_CLUSTER_STATE} \
          --snapshot-count=${local.snapshot_count}
  else
      echo "existing cluster not found -- founding new cluster"
      exec etcd --name $${${local.pod_name_env_var}} --data-dir ${local.data_volume_mount_path}/default.etcd --listen-peer-urls http://0.0.0.0:${local.peer_port} --listen-client-urls http://0.0.0.0:${var.service_port} \
          --advertise-client-urls http://$${HOSTNAME}:${var.service_port},http://${local.service_client_endpoint} \
          --initial-advertise-peer-urls http://$${HOSTNAME}:${local.peer_port} \
          --initial-cluster "$${${local.pod_name_env_var}}=http://$${HOSTNAME}:${local.peer_port}" --initial-cluster-state new --initial-cluster-token ${var.service_name}-cluster \
          --snapshot-count=${local.snapshot_count}
  fi
  EOT

  pre_stop_script = <<-EOT
  ${local.script_globals}
  MEMBER_ID=$(etcdctl member list | grep http://$${IP}:${local.peer_port} | cut -d',' -f1 | cut -d'[' -f1)
  echo "removing $${${local.pod_name_env_var}} from cluster"
  if [ "$ALL_CLIENT_ENDPOINTS" != "" ]; then
      etcdctl member remove --endpoints="$ALL_CLIENT_ENDPOINTS" $MEMBER_ID
  fi
  rm -rf ${local.data_volume_mount_path}/*
  EOT

}

module "service_account" {
  source               = "../common/service-account"
  namespace_name       = var.namespace_name
  service_account_name = var.service_name
}

module "etcd" {
  source               = "../common/stateful"
  cluster_domain       = var.cluster_domain
  namespace_name       = var.namespace_name
  app_name             = var.service_name
  service_account_name = module.service_account.name
  replicas             = 1
  container_image      = var.container_image
  command              = ["/bin/sh", "-ec", local.startup_script]
  pod_resources = {
    cpu_min    = 50
    memory_min = 100
    memory_max = 150
  }
  pod_lifecycle = {
    min_readiness_time    = 15
    max_readiness_time    = 90
    max_cleanup_time      = 30
    shutdown_exec_command = ["/bin/sh", "-ec", local.pre_stop_script]
  }
  pod_probes = {
    port                   = var.service_port
    readiness_path         = "/health"
    liveness_path          = "/health"
    readiness_polling_rate = 5
    liveness_polling_rate  = 5
  }
  persistent_volumes = {
    data = {
      mount_path = "/var/run/etcd"
      size       = 1
    }
  }
  stateless_node_labels = var.stateless_node_labels
  ports = {
    client = {
      port        = var.service_port
      target_port = var.service_port
    }
    peer = {
      port        = local.peer_port
      target_port = local.peer_port
    }
  }
  wait_for_readiness = false
  pod_name_env_var   = local.pod_name_env_var
}
