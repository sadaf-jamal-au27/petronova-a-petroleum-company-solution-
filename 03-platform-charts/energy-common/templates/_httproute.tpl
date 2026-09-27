{{- define "energy-common.httproute" -}}
{{- if and .Values.httpRoute.enabled .Values.service.enabled }}
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: {{ include "energy-common.fullname" . }}
  labels:
    {{- include "energy-common.labels" . | nindent 4 }}
spec:
  parentRefs:
    - name: {{ .Values.httpRoute.gateway.name | default "petronova-gateway" }}
      namespace: {{ .Values.httpRoute.gateway.namespace | default "gateway-infra" }}
      sectionName: https
  hostnames:
    {{- toYaml .Values.httpRoute.hostnames | nindent 4 }}
  rules:
    - matches:
        - path:
            type: PathPrefix
            value: {{ .Values.httpRoute.pathPrefix }}
      {{- if .Values.httpRoute.stripPrefix }}
      filters:
        - type: URLRewrite
          urlRewrite:
            path:
              type: ReplacePrefixMatch
              replacePrefixMatch: /
      {{- end }}
      backendRefs:
        - name: {{ include "energy-common.fullname" . }}
          port: {{ .Values.service.port }}
---
apiVersion: networking.gke.io/v1
kind: HealthCheckPolicy
metadata:
  name: {{ include "energy-common.fullname" . }}
  labels:
    {{- include "energy-common.labels" . | nindent 4 }}
spec:
  default:
    config:
      type: HTTP
      httpHealthCheck:
        port: {{ .Values.service.targetPort }}
        requestPath: {{ .Values.probes.readinessPath }}
  targetRef:
    group: ""
    kind: Service
    name: {{ include "energy-common.fullname" . }}
{{- end }}
{{- end -}}
