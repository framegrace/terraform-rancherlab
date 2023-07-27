#!/bin/bash

RANCHER_API_URL='https://rancher-172.18.0.2.sslip.io/v3'
HELM_CHART_NAME='prometheus-community/kube-state-metrics'
NAMESPACE='cattle-monitoring-system'
RANCHER_ACCESS_KEY='token-8hrs6'
RANCHER_SECRET_KEY='xczx6f6w4f762c2mbhfmx9k7xwfh7gc2t8hfhcv6llkv7484qs9mx6'
RANCHER_TOKEN='token-8hrs6:xczx6f6w4f762c2mbhfmx9k7xwfh7gc2t8hfhcv6llkv7484qs9mx6'

CLUSTER_NAME="$1"

# Retrieve cluster ID for the given cluster name
CLUSTER_ID_RAW=$(curl -k -s -H "Authorization: Bearer $RANCHER_TOKEN" "${RANCHER_API_URL}/clusters?name=$CLUSTER_NAME")
CLUSTER_ID=$(echo "$CLUSTER_ID_RAW" | jq -r '.data[0].id')

echo "Cluster ID  : $CLUSTER_ID"
echo "Cluster Name: $CLUSTER_NAME"

helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

PROJECTS_RAW=$(curl -k -s -H "Authorization: Bearer $RANCHER_TOKEN" "${RANCHER_API_URL}/projects")
#echo "$PROJECTS_RAW" |jq
# Retrieve all projects
PROJECTS=$(echo "$PROJECTS_RAW" | jq -r '.data[] | select(.clusterId == "'$CLUSTER_ID'") | .id + "|" + .name')
echo "$PROJECTS"

for PROJECT in $PROJECTS
do
    ID=$(echo $PROJECT | cut -d "|" -f 1)
    CLUSTER_ID=$(echo $ID | cut -d ":" -f 1)
    PROJECT_ID=$(echo $ID | cut -d ":" -f 2)
    PROJECT_NAME=$(echo $PROJECT | cut -d "|" -f 2)

    # Prepare kube-state-metrics helm values
    CLUSTER_ROLE="${PROJECT_ID}-namespaces-edit" 
    # Deploy or upgrade kube-state-metrics for the project
    helm delete  "dyn-$PROJECT_ID" "$HELM_CHART_NAME" --namespace "$NAMESPACE" 
   #helm upgrade --install "dyn-$PROJECT_ID" "$HELM_CHART_NAME" \
   #    --namespace "$NAMESPACE" \
   #    --set rbac.create=false \
   #    --set rbac.create=false \
   #    --set rbac.useExistingRole=$CLUSTER_ROLE \
   #    --set rbac.useClusterRole=false \
   #    --set customLabels.app=dyn-kube-state-metrics \
   #    --set customLabels.project_name=$PROJECT_NAME \
   #    --set customLabels.project_id=$PROJECT_ID \
   #    --set customLabels.cluster_id=$CLUSTER_ID \
   #    --set customLabels.cluster_name=$CLUSTER_NAME
done
