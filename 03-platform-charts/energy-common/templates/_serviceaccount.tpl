{{- define "energy-common.serviceaccount" -}}
apiVersion: v1
kind: ServiceAccount
metadata:
  name: {{ include "energy-common.fullname" . }}
  labels:
    {{- include "energy-common.labels" . | nindent 4 }}
  {{- with .Values.gcpServiceAccount }}
  annotations:
    iam.gke.io/gcp-service-account: {{ . }}
  {{- end }}
automountServiceAccountToken: false
{{- end -}}
