-include secrets.mk

SERVICE_PORT=80
LOCAL_PORT=8080

.PHONY: setup-jetstack
setup-jetstack:
	helm repo add jetstack https://charts.jetstack.io --force-update
	helm install cert-manager jetstack/cert-manager \
		--namespace cert-manager \
		--create-namespace \
		--version v1.14.5 \
		--set installCRDs=true

.PHONY: setup-agent-operator
setup-agent-operator:
	helm repo add k8s-agents-operator https://newrelic.github.io/k8s-agents-operator
	@helm upgrade --install k8s-agents-operator k8s-agents-operator/k8s-agents-operator \
		--namespace k8s-agents-operator \
		--create-namespace \
		--set licenseKey=${NEW_RELIC_LICENSE_KEY}
	kubectl create namespace php-demo
	@kubectl create secret generic newrelic-key-secret \
		--namespace php-demo \
		--from-literal=new_relic_license_key=${NEW_RELIC_LICENSE_KEY}

.PHONY: setup
setup: setup-jetstack setup-agent-operator

.PHONY: start-redis-leader
start-redis-leader:
	kubectl apply -n php-demo -f redis/redis-leader-deployment.yml
	kubectl apply -n php-demo -f redis/redis-leader-service.yml

.PHONY: start-redis-follower
start-redis-follower:
	kubectl apply -n php-demo -f redis/redis-follower-deployment.yml
	kubectl apply -n php-demo -f redis/redis-follower-service.yml

.PHONY: start-redis
start-redis: start-redis-leader start-redis-follower

.PHONY: start-frontend
start-frontend:
	kubectl apply -n php-demo -f frontend/frontend-deployment.yml
	kubectl apply -n php-demo -f frontend/frontend-service.yml

.PHONY: start-instrumentation
start-instrumentation:
	kubectl apply -n php-demo -f operator/instrumentation.yml

.PHONY: run
run: start-instrumentation start-redis start-frontend
	@echo "Starting service on http://localhost:${LOCAL_PORT}"
	@sleep 2 # this is a hack to give the pods time to start up.
	kubectl wait --for=condition=Ready -n php-demo --all pods
	kubectl port-forward -n php-demo svc/frontend ${LOCAL_PORT}:${SERVICE_PORT}

.PHONY: clean-redis
clean-redis:
	kubectl delete -n php-demo deployment -l app=redis
	kubectl delete -n php-demo service -l app=redis

.PHONY: clean-frontend
clean-frontend:
	kubectl delete -n php-demo deployment frontend
	kubectl delete -n php-demo service frontend

.PHONY: clean-instrumentation
clean-instrumentation:
	kubectl delete -n php-demo -f operator/instrumentation.yml

.PHONY: clean
clean: clean-redis clean-frontend clean-instrumentation

.PHONY: veryclean
veryclean: clean
	kubectl delete secret -n php-demo newrelic-key-secret
	helm uninstall -n cert-manager cert-manager
	kubectl delete namespace php-demo
	kubectl delete namespace k8s-agents-operator
	kubectl delete namespace cert-manager
	helm repo remove k8s-agents-operator
	helm repo remove jetstack

.PHONY: list-deployments
list-deployments:
	@kubectl get deployments -n php-demo

.PHONY: list-services
list-services:
	@kubectl get services -n php-demo

.PHONY: list-pods
list-pods:
	@kubectl get pods -n php-demo

.PHONY: get-instrumentation-deployment
get-instrumentation-deployment:
	kubectl get deployments -o wide -w --namespace k8s-agents-operator k8s-agents-operator-k8s-agents-operator

.PHONY: shell
shell:
	kubectl exec --stdin --tty -n php-demo $(shell kubectl get pods -n php-demo | grep frontend | cut -d ' ' -f 1 | head -1) -- /bin/bash

