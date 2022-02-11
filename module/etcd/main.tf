locals {
  cluster_size            = 3
  client_port             = 2379
  cluster_domain          = "cluster.local"
  peer_port               = 2380
  data_volume_name        = "data"
  data_volume_mount_path  = "/var/run/etcd"
  service_client_endpoint = "${module.service.non_headless_service_hostname}:${local.client_port}"
  startup_script          = <<-EOT
  HOSTNAME=$(hostname)

  # store member id into PVC for later member replacement
  collect_member() {
      while ! etcdctl member list &>/dev/null; do sleep 1; done
      etcdctl member list | grep http://$${HOSTNAME}.${var.namespace_name}.svc.${local.cluster_domain}:${local.peer_port} | cut -d':' -f1 | cut -d'[' -f1 > ${local.data_volume_mount_path}/member_id
      exit 0
  }

  eps() {
      EPS=""
      for i in $$(seq 0 $$((${local.cluster_size} - 1))); do
          EPS="$${EPS}$${EPS:+,}http://${var.service_name}-$${i}.${var.namespace_name}.svc.${local.cluster_domain}:${local.client_port}"
      done
      echo $${EPS}
  }

  member_hash() {
      etcdctl member list | grep http://$${HOSTNAME}.${var.namespace_name}.svc.${local.cluster_domain}:${local.peer_port} | cut -d':' -f1 | cut -d'[' -f1
  }

  # re-joining after failure?
  if [ -e ${local.data_volume_mount_path}/default.etcd ]; then
      echo "Re-joining etcd member"
      member_id=$$(cat ${local.data_volume_mount_path}/member_id)
      # re-join member
      ETCDCTL_ENDPOINT=$$(eps) etcdctl member update $${member_id} http://$${HOSTNAME}.${var.namespace_name}.svc.${local.cluster_domain}:${local.peer_port}
      exec etcd --name $${HOSTNAME} \
          --listen-peer-urls http://${var.service_name}.${var.namespace_name}.svc.${local.cluster_domain}:${local.peer_port} \
          --listen-client-urls http://${var.service_name}.${var.namespace_name}.svc.${local.cluster_domain}:${local.client_port},http://127.0.0.1:${local.client_port} \
          --advertise-client-urls http://${var.service_name}.${var.namespace_name}.svc.${local.cluster_domain}:${local.client_port} \
          --data-dir ${local.data_volume_mount_path}/default.etcd
  fi

  # etcd-SET_ID
  SET_ID=$${HOSTNAME##*-}

  # adding a new member to existing cluster (assuming all initial pods are available)
  if [ "$${SET_ID}" -ge ${local.cluster_size} ]; then
      export ETCDCTL_ENDPOINT=$$(eps)
      # member already added?
      MEMBER_HASH=$$(member_hash)
      if [ -n "$${MEMBER_HASH}" ]; then
          # the member hash exists but for some reason etcd failed
          # as the datadir has not be created, we can remove the member
          # and retrieve new hash
          etcdctl member remove $${MEMBER_HASH}
      fi
      echo "Adding new member"
      etcdctl member add $${HOSTNAME} http://$${HOSTNAME}.${var.namespace_name}.svc.${local.cluster_domain}:${local.peer_port} | grep "^ETCD_" > ${local.data_volume_mount_path}/new_member_envs
      if [ $$? -ne 0 ]; then
          echo "Exiting"
          rm -f ${local.data_volume_mount_path}/new_member_envs
          exit 1
      fi
      cat ${local.data_volume_mount_path}/new_member_envs
      source ${local.data_volume_mount_path}/new_member_envs
      collect_member &
      exec etcd --name $${HOSTNAME} \
          --listen-peer-urls http://${var.service_name}.${var.namespace_name}.svc.${local.cluster_domain}:${local.peer_port} \
          --listen-client-urls http://${var.service_name}.${var.namespace_name}.svc.${local.cluster_domain}:${local.client_port},http://127.0.0.1:${local.client_port} \
          --advertise-client-urls http://${var.service_name}.${var.namespace_name}.svc.${local.cluster_domain}:${local.client_port} \
          --data-dir ${local.data_volume_mount_path}/default.etcd \
          --initial-advertise-peer-urls http://${var.service_name}.${var.namespace_name}.svc.${local.cluster_domain}:${local.peer_port} \
          --initial-cluster $${ETCD_INITIAL_CLUSTER} \
          --initial-cluster-state $${ETCD_INITIAL_CLUSTER_STATE}
  fi

  PEERS=""
  for i in $$(seq 0 $$((${local.cluster_size} - 1))); do
      PEERS="$${PEERS}$${PEERS:+,}${var.service_name}-$${i}=http://${var.service_name}-$${i}.${var.service_name}:${local.peer_port}"
  done

  collect_member &

  # join member
  exec etcd --name $${HOSTNAME} \
      --initial-advertise-peer-urls http://${var.service_name}.${var.namespace_name}.svc.${local.cluster_domain}:${local.peer_port} \
      --listen-peer-urls http://${var.service_name}.${var.namespace_name}.svc.${local.cluster_domain}:${local.peer_port} \
      --listen-client-urls http://${var.service_name}.${var.namespace_name}.svc.${local.cluster_domain}:${local.client_port},http://127.0.0.1:${local.client_port} \
      --advertise-client-urls http://${var.service_name}.${var.namespace_name}.svc.${local.cluster_domain}:${local.client_port} \
      --initial-cluster-token etcd-cluster-1 \
      --initial-cluster $${PEERS} \
      --initial-cluster-state new \
      --data-dir ${local.data_volume_mount_path}/default.etcd

  EOT
  pre_stop_script         = <<-EOT
  EPS=""
  for i in $$(seq 0 $$((${local.cluster_size} - 1))); do
      EPS="$${EPS}$${EPS:+,}http://${var.service_name}-$${i}.${var.namespace_name}.svc.${local.cluster_domain}:${local.client_port}"
  done
  member_hash() {
      etcdctl member list | grep http://${var.service_name}.${var.namespace_name}.svc.${local.cluster_domain}:${local.peer_port} | cut -d':' -f1 | cut -d'[' -f1
  }
  echo "Removing $${HOSTNAME} from etcd cluster"
  ETCDCTL_ENDPOINT=$${EPS} etcdctl member remove $$(member_hash)
  if [ $$? -eq 0 ]; then
      # Remove everything otherwise the cluster will no longer scale-up
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
          command           = ["/bin/sh", "-ec", local.startup_script]
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