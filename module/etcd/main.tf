locals {
  pod_name_env_var         = "POD_NAME"
  snapshot_count           = 1000
  client_port              = var.service_port
  peer_port                = var.service_port + 1
  config_filename          = "config.yaml"
  config_volume_mount_path = "/etc/etcd"
  config_path              = "${local.config_volume_mount_path}/${local.config_filename}"
  data_volume_name         = "data"
  data_volume_mount_path   = "/var/run/etcd"
  service_client_endpoint  = "${module.etcd.hostname}:${var.service_port}"
  domain_suffix            = "${var.service_name}-headless"

  common_options = {
    "data-dir"                                      = "${local.data_volume_mount_path}/default.etcd"
    "listen-client-urls"                            = "http://0.0.0.0:${local.client_port}"
    "listen-peer-urls"                              = "http://0.0.0.0:${local.peer_port}"
    "initial-cluster-token"                         = "${var.service_name}-cluster"
    "snapshot-count"                                = 1000
    "auto-compaction-mode"                          = "periodic"
    "auto-compaction-retention"                     = 1
    "experimental-distributed-tracing-address"      = var.otlp_receiver_endpoint
    "experimental-distributed-tracing-service-name" = var.service_name
  }
  common_args_line = join(" ", [for k, v in local.common_options : "--${k} \"${v}\""])

  script_globals = <<-EOT
  SET_ID="$${${local.pod_name_env_var}##*-}"
  SET_NAME="$${${local.pod_name_env_var}%%-*}"
  HOSTNAME="$${${local.pod_name_env_var}}.${local.domain_suffix}"
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
      MEMBER_ID=$(etcdctl member list --endpoints "$ALL_CLIENT_ENDPOINTS" | grep "http://$${HOSTNAME}:${local.peer_port}" | cut -d',' -f1 | cut -d'[' -f1)
      if [ "$MEMBER_ID" != "" ]; then
          if [ -e ${local.data_volume_mount_path}/default.etcd ] && [ -e ${local.data_volume_mount_path}/new_member_envs ]; then
              echo "cluster present, membership present, local state present => joining as existing member"
              etcdctl member update --endpoints "$ALL_CLIENT_ENDPOINTS" "$MEMBER_ID" --peer-urls "http://$${HOSTNAME}:${local.peer_port}"
          else
              echo "cluster present, membership present, local state NOT present => joining as recreated member"
              etcdctl member remove --endpoints "$ALL_CLIENT_ENDPOINTS" "$MEMBER_ID"
              etcdctl member add --endpoints "$ALL_CLIENT_ENDPOINTS" "$${${local.pod_name_env_var}}" --peer-urls "http://$${HOSTNAME}:${local.peer_port}" | grep "^ETCD_" > ${local.data_volume_mount_path}/new_member_envs
          fi
      else
          echo "cluster present, membership NOT present => joining as new member"
          etcdctl member add --endpoints "$ALL_CLIENT_ENDPOINTS" "$${${local.pod_name_env_var}}" --peer-urls "http://$${HOSTNAME}:${local.peer_port}" | grep "^ETCD_" > ${local.data_volume_mount_path}/new_member_envs
      fi
      . ${local.data_volume_mount_path}/new_member_envs
  else
      echo "cluster NOT present => joining as initial member"
      export ETCD_NAME="$${${local.pod_name_env_var}}"
      export ETCD_INITIAL_CLUSTER="$${${local.pod_name_env_var}}=http://$${HOSTNAME}:${local.peer_port}"
      export ETCD_INITIAL_CLUSTER_STATE="new"
  fi
  exec etcd --advertise-client-urls "http://$${HOSTNAME}:${local.client_port}" \
            --initial-advertise-peer-urls "http://$${HOSTNAME}:${local.peer_port}" \
            --experimental-enable-distributed-tracing \
            --experimental-distributed-tracing-instance-id "$${${local.pod_name_env_var}}" \
            ${local.common_args_line}
  EOT

  pre_stop_script = <<-EOT
  ${local.script_globals}
  MEMBER_ID=$(etcdctl member list | grep http://$${IP}:${local.peer_port} | cut -d',' -f1 | cut -d'[' -f1)
  echo "removing $${${local.pod_name_env_var}} from cluster"
  if [ "$ALL_CLIENT_ENDPOINTS" != "" ]; then
      etcdctl member remove --endpoints="$ALL_CLIENT_ENDPOINTS" "$MEMBER_ID"
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
  command              = ["/bin/sh", "-exc", local.startup_script]
  pod_resources = {
    cpu_min    = 50
    memory_min = 100
    memory_max = 150
  }
  pod_lifecycle = {
    min_readiness_time    = 15
    max_readiness_time    = 90
    max_cleanup_time      = 30
    shutdown_exec_command = ["/bin/sh", "-exc", local.pre_stop_script]
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
      mount_path = local.data_volume_mount_path
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
  wait_for_readiness = true
  pod_name_env_var   = local.pod_name_env_var
}
