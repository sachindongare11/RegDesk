{{/*
Common labels applied to every resource this chart creates.
*/}}
{{- define "regdesk.labels" -}}
app.kubernetes.io/part-of: regdesk
app.kubernetes.io/managed-by: {{ .Release.Service }}
helm.sh/chart: {{ .Chart.Name }}-{{ .Chart.Version }}
{{- end -}}

{{/*
Selector labels for a given service name (e.g. "mcp-tools"). Kept separate
from regdesk.labels because selector labels must never change across
releases/upgrades, while the common labels above safely can.
*/}}
{{- define "regdesk.selectorLabels" -}}
app.kubernetes.io/name: {{ . }}
{{- end -}}

{{/*
emptyDir-backed /tmp, mounted read-write on top of an otherwise read-only
root filesystem. mcp-tools and ingest-worker both use FastEmbed, which
caches its BM25 model under $HF_HOME at first use; agent-api gets the same
mount for consistency (cheap, and plenty of stdlib/third-party code assumes
/tmp is writable). HF_HOME is set alongside this mount in each Deployment's
env so the cache actually lands here instead of failing on a read-only "/".
*/}}
{{- define "regdesk.tmpVolume" -}}
- name: tmp
  emptyDir: {}
{{- end -}}

{{- define "regdesk.tmpVolumeMount" -}}
- name: tmp
  mountPath: /tmp
{{- end -}}
