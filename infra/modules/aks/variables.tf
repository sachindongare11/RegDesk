variable "name" {
  type = string
}

variable "resource_group_name" {
  type = string
}

variable "location" {
  type = string
}

variable "dns_prefix" {
  type = string
}

variable "kubernetes_version" {
  description = <<-EOT
    Pinned explicitly -- an unpinned AKS version drifts to whatever's
    default on apply day, which is exactly the kind of surprise Phase 3's
    version-pinning principle (point 5) is about. 1.36 specifically
    because `az aks get-versions --location centralindia` showed 1.31-1.35
    had all aged out of standard support in this region (LTS-only, an
    extra-cost tier) by the time this was applied -- 1.36.x is the newest
    minor still on regular "KubernetesOfficial" support (1.37 is preview-only).
    Re-check `az aks get-versions` before reusing this default much later.
  EOT
  type        = string
  default     = "1.36"
}

variable "system_node_vm_size" {
  description = "Default node pool: system components plus every regdesk workload except Ollama (see ollama_node_vm_size). Small on purpose -- this is a dev cluster on a $200 credit, not a production system pool."
  type        = string
  default     = "Standard_D2s_v4"
}

variable "system_node_count" {
  description = <<-EOT
    2, not 1: a single Standard_D2s_v4 node reports only ~1.9 vCPU
    allocatable (kubelet/system reservations eat the rest), and AKS's own
    baseline system pods (CoreDNS, CSI drivers, konnectivity, Azure
    Policy, the workload identity webhook, etc.) already use a good
    chunk of that before cert-manager, the RabbitMQ Cluster Operator, and
    KEDA are even installed -- measured 98% requested with KEDA's
    operator pod still Pending, unable to schedule. kind never hit this
    because its single "node" reports the whole host's CPU, not a real
    VM's. 2 nodes (4 vCPU total) fixed it with room to spare, still well
    under the subscription's 10-vCPU regional cap alongside the 4-vCPU
    Ollama pool.
  EOT
  type        = number
  default     = 2
}

variable "ollama_node_vm_size" {
  description = "Dedicated node pool for Ollama, tainted so nothing else schedules there (see the node_taints on azurerm_kubernetes_cluster_node_pool.ollama) -- model memory shouldn't be able to starve the rest of the stack, same lesson Phase 2 learned the hard way about CPU."
  type        = string
  default     = "Standard_D4s_v4"
}

variable "availability_zones" {
  description = "Explicitly 1 and 2 only: zone 3 in Central India is restricted for this subscription's quota on both node sizes above (confirmed via `az vm list-skus`) -- requesting it would fail at apply time."
  type        = list(string)
  default     = ["1", "2"]
}

variable "network_policy" {
  description = "calico or cilium. Calico is the default here to match Phase 2's kind cluster exactly, so the NetworkPolicy manifests already written need zero changes. Azure CNI powered by Cilium is the newer, eBPF-based alternative -- faster, richer flow-log observability, worth knowing as the tradeoff if asked."
  type        = string
  default     = "calico"
}

variable "tags" {
  type    = map(string)
  default = {}
}
