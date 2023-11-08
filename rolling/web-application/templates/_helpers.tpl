{{/*
Expand the name of the chart.
*/}}
{{- define "web-application.internal.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "web-application.internal.fullname" -}}
  {{- if .Values.fullnameOverride }}
    {{- if gt (len .Values.fullnameOverride) 63 }}
      {{- fail (printf "name exceeds 63 characters: '%s'" .Values.fullnameOverride) }}
    {{- end }}
    {{- .Values.fullnameOverride }}
  {{- else }}
    {{- $name := default .Chart.Name .Values.nameOverride }}
    {{- if not (eq .Release.Name $name)}}
      {{- $name = printf "%s-%s" .Release.Name $name }}
    {{- end }}
    {{- if gt (len $name) 63 }}
      {{- fail (printf "name exceeds 63 characters: '%s'" $name) }}
    {{- end }}
    {{- $name }}
  {{- end }}
{{- end }}

{{/*
*/}}
{{- define "web-application.internal.bindingName" -}}
{{- printf "%s-%s" (include "web-application.internal.fullname" .root ) .name }}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "web-application.internal.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "web-application.internal.labels" -}}
helm.sh/revision: {{ .Release.Revision | quote }}
helm.sh/chart: {{ include "web-application.internal.chart" . }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{ include "web-application.internal.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "web-application.internal.selectorLabels" -}}
app.kubernetes.io/name: {{ include "web-application.internal.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- if .Values.global}}
{{- if .Values.global.component }}
app.kubernetes.io/component:{{ .Values.global.component }}
{{- end }}
{{- if .Values.global.partOf }}
app.kubernetes.io/partOf: {{ .Values.global.partOf }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Define Host for the APIRule
*/}}
{{- define "web-application.internal.exposeHost" -}}
{{- if .Values.expose.host }}
{{- tpl .Values.expose.host . }}
{{- else }}
{{- $name := (include "web-application.internal.fullname" .) }}
{{- if hasPrefix $name .Release.Namespace }}
{{- .Release.Namespace }}
{{- else }}
{{- printf "%s-%s" $name .Release.Namespace | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Define the application uri which will be used for the VCAP_APPLICATION env variable
*/}}
{{- define "web-application.internal.applicationUri" -}}
{{- include "web-application.internal.fullname" . }}
{{- end }}

{{/*
Service Binding secret mounts
*/}}
{{- define "web-application.internal.serviceMounts" -}}
{{- $bindings := omit .Values.bindings "defaultProperties" -}}
{{- range $name, $params := $bindings }}
- mountPath: /bindings/{{ $name }}/
  name: "{{ $name }}"
  readOnly: true
{{- end }}
{{- end }}

{{/*
Service Binding secret volumes
*/}}
{{- define "web-application.internal.serviceVolumes" -}}
{{- $bindings := omit .Values.bindings "defaultProperties" -}}
{{- range $name, $params := $bindings }}
{{- $secretName := (include "web-application.internal.bindingName" (dict "root" $ "name" $name)) }}
{{- if $params.fromSecret }}
{{- $secretName = $params.fromSecret}}
{{- else if $params.secretName }}
{{- $secretName = $params.secretName }}
{{- end }}
- name: {{ $name }}
  secret:
    secretName: {{ tpl $secretName $ }}
{{- end }}
{{- end }}

{{/*
Name of the imagePullSecret
*/}}
{{- define "web-application.internal.imagePullSecretName" -}}
{{ $ips := (dict "local" .Values.imagePullSecret "global" .Values.global.imagePullSecret) }}
{{- if $ips.local.name }}
{{- $ips.local.name }}
{{- else if $ips.global.name }}
{{- $ips.global.name }}
{{- else if or $ips.local.dockerconfigjson $ips.global.dockerconfigjson }}
{{- include "web-application.internal.fullname" . }}
{{- end }}
{{- end }}

{{/*
Calculate the final image name
*/}}
{{- define "web-application.internal.imageName" -}}
{{- $tag := .Values.image.tag | default .Values.global.image.tag | default "latest" }}
{{- $registry := .Values.image.registry | default .Values.global.image.registry }}
{{- if $registry }}
{{- $registry | trimSuffix "/" }}/{{ .Values.image.repository }}:{{ $tag }}
{{- else }}
{{- .Values.image.repository }}:{{ $tag }}
{{- end }}
{{- end }}

{{/*
Create the name of a service instance.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as service instance name.
*/}}
{{- define "web-application.internal.serviceInstanceName" -}}
  {{- $name := "" }}
  {{- if .binding.serviceInstanceFullname }}
    {{- if gt (len .binding.serviceInstanceFullname) 63 }}
      {{- fail (printf "name exceeds 63 characters: '%s'" .binding.serviceInstanceFullname) }}
    {{- end }}
    {{- $name = .binding.serviceInstanceFullname }}
  {{- else }}
    {{- $name = .binding.serviceInstanceName }}
    {{- if not (hasPrefix .root.Release.Name $name)}}
      {{- $name = printf "%s-%s" .root.Release.Name $name }}
    {{- end }}
    {{- if gt (len $name) 63 }}
      {{- fail (printf "name exceeds 63 characters: '%s'" $name) }}
    {{- end }}
  {{- end }}
  {{- tpl $name .root }}
{{- end }}

{{- define "web-application.internal.processEnv" -}}
{{- $result := dict }}
{{- $variables := list }}
{{- range $k, $v := .Values.env }}
  {{- $variable := dict }}
  {{/*
    We support two versions to provide environment variables: as an array and as a map

    env:
    - name: TEST
      value: X

    env:
      TEST: X

    Transform the map case into the array case:
  */}}
  {{- if (not (kindIs "map" $v)) }}
    {{- $v = (dict "value" $v) }}
  {{- end }}
  {{- if (kindIs "string" $k) }} {{/* $k will be the array index (therefore int) in the array case */}}
    {{- $_ := (set $v "name" $k) }}
  {{- end }}

  {{/* we have defaults for APPLICATION_NAME and APPLICATION_URI, but only want to provide them, if the users has no explicit values. */}}
  {{- if eq "APPLICATION_NAME" $v.name }}
    {{- $_ := set $result "appName" true }}
  {{- end }}
  {{- if eq "APPLICATION_URI" $v.name }}
    {{- $_ := set $result "appURI" true }}
  {{- end }}

  {{/* Translate into K8s struct */}}
  {{- $_ := set $variable "name" $v.name }}
  {{- if $v.value }}
    {{- $_ := set $variable "value" ($v.value | toString) }}
  {{- else }}
    {{- $_ := set $variable "valueFrom" (omit $v "name")}}
  {{- end }}
  {{- $variables = append $variables $variable}}
{{- end }}
{{- $_ := set $result "vars" $variables }}
 {{- (fromYaml (tpl (toYaml $result) $)) | mustToJson }}
{{- end }}

{{- define "web-application.internal.processEnvFrom" -}}
{{- $result := dict }}
{{- $variables := list }}
{{- range $envFrom := .Values.envFrom }}
  {{- $variables = append $variables $envFrom }}
{{- end }}
{{- $_ := set $result "vars" $variables }}
{{- (fromYaml (tpl (toYaml $result) $)) | mustToJson }}
{{- end }}
