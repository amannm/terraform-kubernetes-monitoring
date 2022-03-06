locals {
  traces_config = {
    configs = [
      {
        name = "default"
        remote_write = [
          {
            endpoint = var.remote_write_endpoint
            protocol = "grpc"
            format   = "otlp"
            insecure = true
          }
        ]
        receivers = {
          zipkin = {
            endpoint = "0.0.0.0:${var.zipkin_receiver_port}"
          }
          jaeger = {
            protocols = {
              thrift_http = {
                endpoint = "0.0.0.0:${var.jaeger_receiver_port}"
              }
            }
          }
        }
        scrape_configs = [
          {
            job_name          = "kubernetes-pods"
            scheme            = "https"
            bearer_token_file = "/var/run/secrets/kubernetes.io/serviceaccount/token"
            tls_config = {
              ca_file              = "/var/run/secrets/kubernetes.io/serviceaccount/ca.crt"
              insecure_skip_verify = true
            }
            kubernetes_sd_configs = [
              {
                role = "pod"
              }
            ]
            relabel_configs = [
              {
                source_labels = ["__meta_kubernetes_namespace"]
                target_label  = "namespace"
              },
              {
                source_labels = ["__meta_kubernetes_pod_name"]
                target_label  = "pod"
              },
              {
                source_labels = ["__meta_kubernetes_container_name"]
                target_label  = "container"
              },
            ]
          }
        ]
        automatic_logging = {
          backend            = "logs_instance"
          logs_instance_name = var.logs_instance_name
          spans              = true
          roots              = true
          processes          = true
        }
      }
    ]
  }
}
