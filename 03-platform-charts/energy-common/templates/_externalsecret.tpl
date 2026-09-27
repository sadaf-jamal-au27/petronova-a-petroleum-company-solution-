{{- define "energy-common.externalsecret" -}}
{{- if .Values.externalSecret.enabled }}
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: {{ include "energy-common.fullname" . }}
  labels:
    {{- include "energy-common.labels" . | nindent 4 }}
spec:
  refreshInterval: {{ .Values.externalSecret.refreshInterval | default "1h" }}
  secretStoreRef:
    kind: ClusterSecretStore
    name: {{ .Values.externalSecret.storeName | default "gcp-secret-manager" }}
  target:
    name: {{ include "energy-common.fullname" . }}-secrets
    creationPolicy: Owner
  data:
    {{- range .Values.externalSecret.keys }}
    - secretKey: {{ .envName }}
      remoteRef:
        key: {{ .gsmName }}
        {{- with .version }}
        version: {{ . | quote }}
        {{- end }}
    {{- end }}
{{- end }}
{{- end -}}
