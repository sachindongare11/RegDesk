variable "display_name" {
  description = "Name for the Entra ID application registration."
  type        = string
}

variable "github_repo" {
  description = "owner/repo, e.g. sachindongare11/RegDesk."
  type        = string
}

variable "github_refs" {
  description = <<-EOT
    Git refs this identity can be used from, as GitHub OIDC subject
    suffixes (e.g. "ref:refs/heads/main" for pushes to main,
    "pull_request" for PR-triggered runs). Scoped deliberately narrow --
    Phase 4's CI/CD workflow only needs Azure credentials on the
    merge-to-main job (building and pushing images); the PR-time checks
    (ruff, pytest, terraform fmt/tflint/checkov) are all local static
    analysis with no Azure access at all, so they're not included here
    even though they also run via GitHub Actions.
  EOT
  type        = list(string)
  default     = ["ref:refs/heads/main"]
}
