{{- define "openldap.name" -}}{{ .Chart.Name }}{{- end -}}
{{- define "openldap.fullname" -}}{{ .Release.Name }}{{- end -}}
{{- define "openldap.labels" -}}
app.kubernetes.io/name: {{ include "openldap.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
helm.sh/chart: {{ .Chart.Name }}-{{ .Chart.Version }}
{{- end -}}
{{- define "openldap.selector" -}}
app.kubernetes.io/name: {{ include "openldap.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}
{{- define "openldap.secretName" -}}{{ default (printf "%s-env" (include "openldap.fullname" .)) .Values.ldap.existingSecret }}{{- end -}}
{{- define "openldap.claimName" -}}{{ default (printf "%s-data" (include "openldap.fullname" .)) .Values.persistence.existingClaim }}{{- end -}}
