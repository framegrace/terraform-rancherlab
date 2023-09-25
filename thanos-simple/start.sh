#!/bin/bash
killall kubectl
docker stop querier
docker stop grafana
docker rm grafana
#NAMESPACES="$(kubectl get namespaces |grep cattle-project|grep monitoring|sed 's/\([^ ]*\).*$/\1/')"
#for NS in $NAMESPACES; do
  #echo "->$NS"
#done
kubectl config use-context kind-upc-sample-0
kubectl port-forward  -n cattle-project-p-skn98-monitoring prometheus-cattle-project-p-skn98-mon-prometheus-0 19191:19191 > /tmp/log1 2>&1 &
kubectl port-forward  -n cattle-project-p-fr98l-monitoring prometheus-cattle-project-p-fr98l-mon-prometheus-0 19291:19191 > /tmp/log2 2>&1 &
kubectl config use-context kind-upc-sample-1
kubectl port-forward  -n cattle-project-p-rf7kf-monitoring prometheus-cattle-project-p-rf7kf-mon-prometheus-0 19391:19191 > /tmp/log1 2>&1 &
kubectl port-forward  -n cattle-project-p-rsrhj-monitoring prometheus-cattle-project-p-rsrhj-mon-prometheus-0 19491:19191 > /tmp/log2 2>&1 &
kubectl port-forward  -n cattle-project-p-wj44d-monitoring prometheus-cattle-project-p-wj44d-mon-prometheus-0 19591:19191 > /tmp/log2 2>&1 &
# Project A alone
docker run -d --net=host --rm \
    --name querier \
    quay.io/thanos/thanos:v0.28.0 \
    query \
    --http-address 0.0.0.0:29091 \
    --grpc-address 0.0.0.0:29191 \
    --query.replica-label replica \
    --store 127.0.0.1:19191 \
    --store 127.0.0.1:19291 \
    --store 127.0.0.1:19391 \
    --store 127.0.0.1:19491 \
    --store 127.0.0.1:19591 && echo "Started Thanos 01-02 Querier"
docker run -d -p 3000:3000 --net=host --volume grafana-storage:/var/lib/grafana --name=grafana grafana/grafana-enterprise

