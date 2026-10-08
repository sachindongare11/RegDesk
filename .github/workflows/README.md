# .github/workflows/

CI pipelines, populated in **Phase 4**:

- On every pull request: `ruff`, `pytest` for each service, `terraform fmt
  -check`, `tflint`, `checkov`.
- On merge to `main`: build each service image, scan with Trivy (fail on
  HIGH/CRITICAL), push to ACR tagged with the git SHA, then commit the new
  tag into `deploy/charts/regdesk/values-dev.yaml` so Argo CD picks it up.
