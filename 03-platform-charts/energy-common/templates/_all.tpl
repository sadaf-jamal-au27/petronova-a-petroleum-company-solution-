{{/* Render every object that applies to this workload. */}}
{{- define "energy-common.all" -}}
{{ include "energy-common.serviceaccount" . }}
{{- if eq (.Values.workload.kind | default "Deployment") "CronJob" }}
---
{{ include "energy-common.cronjob" . }}
{{- else }}
---
{{ include "energy-common.deployment" . }}
{{- end }}
{{- $objs := list "energy-common.service" "energy-common.configmap" "energy-common.hpa" "energy-common.pdb" "energy-common.networkpolicy" "energy-common.externalsecret" "energy-common.httproute" "energy-common.podmonitoring" }}
{{- range $objs }}
{{- $out := include . $ | trim }}
{{- if $out }}
---
{{ $out }}
{{- end }}
{{- end }}
{{- end -}}
