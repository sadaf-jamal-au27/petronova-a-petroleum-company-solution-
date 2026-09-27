{{- define "energy-common.podmonitoring" -}}
{{- if and .Values.metrics.enabled .Values.service.enabled }}
apiVersion: monitoring.googleapis.com/v1
kind: PodMonitoring
metadata:
  name: {{ include "energy-common.fullname" . }}
  labels:
    {{- include "energy-common.labels" . | nindent 4 }}
spec:
  selector:
    matchLabels:
      {{- include "energy-common.selectorLabels" . | nindent 6 }}
  endpoints:
    - port: http
      path: {{ .Values.metrics.path | default "/metrics" }}
      interval: {{ .Values.metrics.interval | default "30s" }}
{{- end }}
{{- end -}}
