{{/* Name of the workload: chart name unless overridden */}}
{{- define "energy-common.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "energy-common.fullname" -}}
{{- include "energy-common.name" . -}}
{{- end -}}

{{- define "energy-common.selectorLabels" -}}
app.kubernetes.io/name: {{ include "energy-common.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{- define "energy-common.labels" -}}
{{ include "energy-common.selectorLabels" . }}
app.kubernetes.io/version: {{ .Values.image.tag | default .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/part-of: petronova
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" }}
petronova.io/team: {{ required "team is required" .Values.team | quote }}
petronova.io/data-classification: {{ .Values.dataClassification | default "internal" | quote }}
{{- end -}}

{{- define "energy-common.image" -}}
{{- $tag := .Values.image.tag | default .Chart.AppVersion -}}
{{- if .Values.image.digest -}}
{{ .Values.image.repository }}@{{ .Values.image.digest }}
{{- else -}}
{{ .Values.image.repository }}:{{ $tag }}
{{- end -}}
{{- end -}}

{{/* Secure pod spec shared by Deployment and CronJob */}}
{{- define "energy-common.podSpec" -}}
serviceAccountName: {{ include "energy-common.fullname" . }}
automountServiceAccountToken: {{ .Values.automountServiceAccountToken | default false }}
{{- with .Values.priorityClassName }}
priorityClassName: {{ . }}
{{- end }}
securityContext:
  runAsNonRoot: true
  runAsUser: {{ .Values.podSecurity.runAsUser | default 65532 }}
  runAsGroup: {{ .Values.podSecurity.runAsUser | default 65532 }}
  fsGroup: {{ .Values.podSecurity.runAsUser | default 65532 }}
  seccompProfile:
    type: RuntimeDefault
{{- with .Values.nodeSelector }}
nodeSelector:
  {{- toYaml . | nindent 2 }}
{{- end }}
{{- with .Values.tolerations }}
tolerations:
  {{- toYaml . | nindent 2 }}
{{- end }}
{{- if .Values.cloudSqlProxy.enabled }}
initContainers:
  - name: cloud-sql-proxy
    image: {{ .Values.cloudSqlProxy.image }}
    restartPolicy: Always
    args:
      - --auto-iam-authn
      - --private-ip
      - --structured-logs
      - --port={{ .Values.cloudSqlProxy.port }}
      - --health-check
      - --http-address=0.0.0.0
      - {{ required "cloudSqlProxy.instance is required" .Values.cloudSqlProxy.instance | quote }}
    startupProbe:
      httpGet: { path: /startup, port: 9090 }
      periodSeconds: 1
      failureThreshold: 60
    securityContext:
      allowPrivilegeEscalation: false
      readOnlyRootFilesystem: true
      runAsNonRoot: true
      capabilities: { drop: ["ALL"] }
    resources:
      requests: { cpu: 50m, memory: 64Mi }
      limits: { memory: 128Mi }
{{- end }}
containers:
  - name: app
    image: {{ include "energy-common.image" . | quote }}
    imagePullPolicy: IfNotPresent
    {{- with .Values.command }}
    command:
      {{- toYaml . | nindent 6 }}
    {{- end }}
    {{- with .Values.args }}
    args:
      {{- toYaml . | nindent 6 }}
    {{- end }}
    {{- if .Values.service.enabled }}
    ports:
      - name: http
        containerPort: {{ .Values.service.targetPort }}
        protocol: TCP
    {{- end }}
    env:
      - name: POD_NAMESPACE
        valueFrom: { fieldRef: { fieldPath: metadata.namespace } }
      - name: SERVICE_NAME
        value: {{ include "energy-common.name" . | quote }}
      {{- with .Values.env }}
      {{- toYaml . | nindent 6 }}
      {{- end }}
    {{- if or .Values.config .Values.externalSecret.enabled }}
    envFrom:
      {{- if .Values.config }}
      - configMapRef:
          name: {{ include "energy-common.fullname" . }}
      {{- end }}
      {{- if .Values.externalSecret.enabled }}
      - secretRef:
          name: {{ include "energy-common.fullname" . }}-secrets
      {{- end }}
    {{- end }}
    securityContext:
      allowPrivilegeEscalation: false
      readOnlyRootFilesystem: true
      capabilities:
        drop: ["ALL"]
    resources:
      {{- required "resources are required (requests.cpu/memory at minimum)" .Values.resources | toYaml | nindent 6 }}
    {{- if and .Values.service.enabled .Values.probes.enabled }}
    readinessProbe:
      httpGet: { path: {{ .Values.probes.readinessPath }}, port: http }
      periodSeconds: 10
      failureThreshold: 3
    livenessProbe:
      httpGet: { path: {{ .Values.probes.livenessPath }}, port: http }
      initialDelaySeconds: 15
      periodSeconds: 20
    {{- end }}
    volumeMounts:
      - name: tmp
        mountPath: /tmp
      {{- with .Values.extraVolumeMounts }}
      {{- toYaml . | nindent 6 }}
      {{- end }}
volumes:
  - name: tmp
    emptyDir: {}
  {{- with .Values.extraVolumes }}
  {{- toYaml . | nindent 2 }}
  {{- end }}
{{- end -}}
