variable "display_name" {
  description = "Name for the Entra ID application registration."
  type        = string
}

variable "github_repo" {
  description = <<-EOT
    The exact `sub` claim prefix GitHub issues for this repo -- NOT
    simply "owner/repo". GitHub's "immutable subject" feature (the
    account-wide default as of this writing: confirm with
    `gh api repos/<owner>/<repo>/actions/oidc/customization/sub`) bakes
    the numeric owner and repository IDs into the subject as
    "owner@owner_id/repo@repo_id", specifically so a repo rename, a
    delete-then-recreate with the same name, or a transfer can never
    let a *different* repo satisfy an old federated credential's
    subject match. Get both IDs from that same `gh api` call's
    `sub_claim_prefix` field (or GET /repos/{owner}/{repo} for the repo
    ID and GET /users/{owner} for the owner ID) -- a plain "owner/repo"
    here will authenticate successfully right up until it's asked to
    issue a real token, where Azure AD rejects it with
    AADSTS700213 for not matching anything.
  EOT
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
