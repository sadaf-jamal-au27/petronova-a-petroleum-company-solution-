{{/*
Per-app ingress allow-list. The tenant chart applies default-deny, so a workload
only receives traffic from the apps listed here, the Gateway (if exposed) and
Managed Prometheus. With nothing listed, no ingress rule is rendered (deny).
*/}}
{{- define "energy-common.networkpolicy" -}}
{{- if and .Values.networkPolicy.enabled .Values.service.enabled }}
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: {{ include "energy-common.fullname" . }}
  labels:
    {{- include "energy-common.labels" . | nindent 4 }}
spec:
  podSelector:
    matchLabels:
      {{- include "energy-common.selectorLabels" . | nindent 6 }}
  policyTypes: ["Ingress"]
  {{- if or .Values.networkPolicy.allowFrom .Values.httpRoute.enabled }}
  ingress:
    - ports:
        - port: {{ .Values.service.targetPort }}
          protocol: TCP
      from:
        {{- range .Values.networkPolicy.allowFrom }}
        - podSelector:
            matchLabels:
              app.kubernetes.io/name: {{ .app }}
          {{- if .namespace }}
          namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: {{ .namespace }}
          {{- end }}
        {{- end }}
        {{- if .Values.httpRoute.enabled }}
        - ipBlock: { cidr: 35.191.0.0/16 }
        - ipBlock: { cidr: 130.211.0.0/22 }
        {{- with .Values.networkPolicy.proxyOnlySubnet }}
        - ipBlock: { cidr: {{ . }} }
        {{- end }}
        {{- end }}
  {{- else }}
  ingress: []
  {{- end }}
{{- end }}
{{- end -}}
