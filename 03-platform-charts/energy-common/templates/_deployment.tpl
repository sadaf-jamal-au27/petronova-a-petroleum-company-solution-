{{- define "energy-common.deployment" -}}
apiVersion: apps/v1
kind: Deployment
metadata:
  name: {{ include "energy-common.fullname" . }}
  labels:
    {{- include "energy-common.labels" . | nindent 4 }}
spec:
  {{- if not .Values.autoscaling.enabled }}
  replicas: {{ .Values.replicaCount }}
  {{- end }}
  revisionHistoryLimit: 5
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxSurge: 1
      maxUnavailable: 0
  selector:
    matchLabels:
      {{- include "energy-common.selectorLabels" . | nindent 6 }}
  template:
    metadata:
      labels:
        {{- include "energy-common.labels" . | nindent 8 }}
      annotations:
        checksum/config: {{ .Values.config | toJson | sha256sum }}
        {{- with .Values.podAnnotations }}
        {{- toYaml . | nindent 8 }}
        {{- end }}
    spec:
      {{- include "energy-common.podSpec" . | nindent 6 }}
      topologySpreadConstraints:
        - maxSkew: 1
          topologyKey: topology.kubernetes.io/zone
          whenUnsatisfiable: ScheduleAnyway
          labelSelector:
            matchLabels:
              {{- include "energy-common.selectorLabels" . | nindent 14 }}
        - maxSkew: 1
          topologyKey: kubernetes.io/hostname
          whenUnsatisfiable: ScheduleAnyway
          labelSelector:
            matchLabels:
              {{- include "energy-common.selectorLabels" . | nindent 14 }}
{{- end -}}
