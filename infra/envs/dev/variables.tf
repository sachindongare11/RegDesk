variable "project" {
  type    = string
  default = "regdesk"
}

variable "environment" {
  type    = string
  default = "dev"
}

variable "location" {
  type    = string
  default = "centralindia"
}

variable "tags" {
  type = map(string)
  default = {
    project     = "regdesk"
    environment = "dev"
  }
}

# -- ingest-worker's workload identity --
# Must match the ServiceAccount regdesk's Helm chart creates for
# ingest-worker (deploy/charts/regdesk/templates/ingest-worker/serviceaccount.yaml)
# once that chart is deployed to this cluster -- the federated credential's
# subject is namespace:serviceaccount-name, and a mismatch here means the
# federation silently never matches, not an error at apply time.
variable "ingest_worker_namespace" {
  type    = string
  default = "regdesk"
}

variable "ingest_worker_service_account" {
  type    = string
  default = "ingest-worker"
}
