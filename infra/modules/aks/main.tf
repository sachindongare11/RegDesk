# This module owns only what's generic to "an AKS cluster for regdesk" --
# the cluster itself, its two node pools, and the network/identity settings
# that make Phase 2's manifests and Phase 3's workload-identity plan work.
#
# What it deliberately does NOT own, because they're consumer-specific
# rather than generic to any cluster using this module:
#   - The ingest-worker workload identity + federated credential (point 4
#     of the Phase 3 spec) -- that's specific to one namespace/ServiceAccount
#     name and lives in infra/envs/dev instead, wired against this module's
#     oidc_issuer_url output.
#   - The kubelet identity's AcrPull role assignment -- also in envs/dev,
#     since it needs this module's kubelet_identity_object_id output AND
#     the ACR module's id, and assigning a role is a relationship between
#     two resources, not a property of either one alone.

resource "azurerm_kubernetes_cluster" "this" {
  name                = var.name
  resource_group_name = var.resource_group_name
  location            = var.location
  dns_prefix          = var.dns_prefix
  kubernetes_version  = var.kubernetes_version
  tags                = var.tags

  # checkov:skip=CKV_AZURE_170: the paid SLA tier (sku_tier = "Standard")
  # costs real money per hour for an API-server uptime guarantee this dev
  # cluster, meant to be destroyed and rebuilt freely, doesn't need. Free
  # tier (default) is the right choice here; a real environment serving
  # traffic would pay for Standard.
  # checkov:skip=CKV_AZURE_115: a private cluster needs a VPN or private
  # network to reach the API server from -- not set up for this dev
  # subscription, same tradeoff as the storage account and Key Vault's
  # public-access settings elsewhere in infra/.
  # checkov:skip=CKV_AZURE_6: authorized IP ranges would need to track
  # this laptop's public IP, which isn't static -- same "no VPN/fixed
  # network set up yet" family of tradeoff as the private-cluster skip
  # above.
  # checkov:skip=CKV_AZURE_4: AKS -> Azure Monitor logging is explicitly
  # Phase 5's scope (observability: OpenTelemetry, Prometheus, Grafana --
  # see the repo root README's phase plan), not an oversight here. Wiring
  # it now would mean designing the logging/metrics pipeline twice, and
  # Log Analytics ingestion has its own ongoing cost worth deciding on
  # deliberately in that phase, not as a side effect of this one.

  # SystemAssigned, not user-assigned, for the control plane identity
  # itself: AKS manages its lifecycle automatically and there's nothing
  # else that needs to reference this specific identity by a stable
  # resource ID the way the ingest-worker workload identity does (see
  # infra/envs/dev). Simpler, one less resource, same security posture.
  identity {
    type = "SystemAssigned"
  }

  # checkov:skip=CKV_AZURE_232: everything except Ollama runs on this one
  # pool (system components + the regdesk app workloads) rather than
  # splitting system-critical-only onto its own third pool -- the
  # approved Phase 3 sizing is two pools (this one, plus the dedicated
  # Ollama pool below) to stay well under the subscription's 10-vCPU
  # regional quota. A dedicated system-only pool is the natural next step
  # if this cluster ever becomes more than a dev environment.
  default_node_pool {
    name       = "system"
    vm_size    = var.system_node_vm_size
    node_count = var.system_node_count
    zones      = var.availability_zones
    # checkov:skip=CKV_AZURE_168: default (30) is already well above this
    # cluster's actual pod count; raised anyway since it costs nothing.
    max_pods = 50
    # checkov:skip=CKV_AZURE_226: ephemeral OS disks need the OS disk size
    # to fit inside the VM size's local cache -- not verified against
    # this workload's actual local storage needs (container images plus
    # any emptyDir usage), and a miscalculation here fails at node
    # provisioning time, not at `terraform plan`. Managed disks are the
    # safer default until that's actually measured.

    upgrade_settings {
      max_surge = "10%"
    }
  }

  # checkov:skip=CKV_AZURE_117: customer-managed-key disk encryption adds a
  # Key Vault dependency and real setup complexity for marginal benefit
  # over Azure's platform-managed encryption-at-rest, which already
  # applies by default. Worth revisiting if this ever holds production
  # data.
  # checkov:skip=CKV_AZURE_227: host-based encryption needs the
  # Microsoft.Compute/EncryptionAtHost feature registered on the
  # subscription first (`az feature register`), which hasn't been done --
  # deferred rather than risking an apply-time failure on an unregistered
  # feature.

  # Local admin kubeconfig disabled -- every kubectl session authenticates
  # through Entra ID instead (same principle as the workload identity
  # federation above, just for human access instead of a pod's). The
  # tradeoff: `az aks get-credentials` now needs `kubelogin`, and every
  # kubectl session does an interactive (or device-code) Entra ID login
  # the first time -- see infra/envs/dev/README.md for the resulting
  # workflow. azure_rbac_enabled means access is granted via ordinary
  # azurerm_role_assignment resources (see envs/dev), not a static admin
  # group list.
  local_account_disabled = true
  azure_active_directory_role_based_access_control {
    tenant_id          = data.azurerm_client_config.current.tenant_id
    azure_rbac_enabled = true
  }

  # Free, zero-downside hardening: Azure Policy's Gatekeeper-based
  # admission controller, and auto-upgrading to new patch releases only
  # (never a minor version bump that could drift from the pinned
  # kubernetes_version unexpectedly).
  azure_policy_enabled      = true
  automatic_upgrade_channel = "patch"

  # OIDC issuer + workload identity: the two settings that let a pod's
  # Kubernetes ServiceAccount federate directly with an Azure AD identity
  # and request tokens with no secret stored anywhere, in-cluster or
  # otherwise. workload_identity_enabled alone does nothing without
  # oidc_issuer_enabled -- the federation needs this cluster's own OIDC
  # issuer URL to trust against (exposed below as oidc_issuer_url).
  oidc_issuer_enabled       = true
  workload_identity_enabled = true

  # Lets pods mount Key Vault secrets directly (CSI driver) or sync them
  # into native Kubernetes Secrets, instead of a human copy-pasting
  # `az keyvault secret show` output into a Helm value or a manually
  # created Secret -- which is exactly what Phase 2 had to do by hand for
  # RabbitMQ's credentials.
  key_vault_secrets_provider {
    secret_rotation_enabled  = true
    secret_rotation_interval = "2m"
  }

  network_profile {
    network_plugin = "azure"
    # Azure CNI (not kubenet): required for the Key Vault CSI driver's
    # pod-identity-style networking and for Calico/Cilium network policy
    # enforcement below -- kubenet doesn't support either cleanly.
    network_policy = var.network_policy == "calico" ? "calico" : null
    # Azure CNI Powered by Cilium is a different knob than network_policy
    # (network_data_plane, not network_policy = "cilium") -- see
    # variables.tf's comment on this tradeoff.
    network_data_plane  = var.network_policy == "cilium" ? "cilium" : "azure"
    network_plugin_mode = var.network_policy == "cilium" ? "overlay" : null
  }
}

# A separate, dedicated pool for Ollama: model memory shouldn't be able to
# starve CoreDNS, cert-manager, KEDA, or any of the other services sharing
# the default pool. The taint means nothing schedules here by default --
# the Helm chart's Ollama deployment needs a matching toleration (and a
# nodeSelector/affinity on this pool's label) added when it's deployed to
# this cluster instead of kind.
resource "azurerm_kubernetes_cluster_node_pool" "ollama" {
  name                  = "ollama"
  kubernetes_cluster_id = azurerm_kubernetes_cluster.this.id
  vm_size               = var.ollama_node_vm_size
  node_count            = 1
  zones                 = var.availability_zones
  mode                  = "User"
  # checkov:skip=CKV_AZURE_227: see the matching skip on the cluster's
  # default_node_pool above -- same unregistered subscription feature.
  # checkov:skip=CKV_AZURE_168: see the matching skip on the cluster's
  # default_node_pool above -- same reasoning, raised for consistency.
  max_pods = 50

  node_labels = {
    workload = "ollama"
  }
  node_taints = [
    "workload=ollama:NoSchedule"
  ]
}
