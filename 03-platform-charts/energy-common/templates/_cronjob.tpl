{{- define "energy-common.cronjob" -}}
apiVersion: batch/v1
kind: CronJob
metadata:
  name: {{ include "energy-common.fullname" . }}
  labels:
    {{- include "energy-common.labels" . | nindent 4 }}
spec:
  schedule: {{ required "workload.schedule is required for CronJob" .Values.workload.schedule | quote }}
  timeZone: {{ .Values.workload.timeZone | default "Asia/Kolkata" | quote }}
  concurrencyPolicy: Forbid
  successfulJobsHistoryLimit: 3
  failedJobsHistoryLimit: 3
  jobTemplate:
    spec:
      backoffLimit: {{ .Values.workload.backoffLimit | default 2 }}
      activeDeadlineSeconds: {{ .Values.workload.activeDeadlineSeconds | default 3600 }}
      template:
        metadata:
          labels:
            {{- include "energy-common.labels" . | nindent 12 }}
        spec:
          restartPolicy: Never
          {{- include "energy-common.podSpec" . | nindent 10 }}
{{- end -}}
