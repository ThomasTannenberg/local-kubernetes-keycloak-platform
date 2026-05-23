.PHONY: vm-create vm-delete cluster-create cluster-delete fleet-bootstrap fleet-status install validate cleanup

KUBECONFIG_FILE := cluster/ansible/k3s.yaml

vm-create:
	cd cluster/libvirt && ./00-bootstrap.sh
	cd cluster/libvirt && ./01-deploy-cluster-cloudimg.sh

vm-delete:
	cd cluster/libvirt && ./99-cleanup.sh

cluster-create:
	cd cluster/ansible && ansible-playbook site.yml

cluster-delete:
	cd cluster/ansible && ansible-playbook uninstall.yml

fleet-bootstrap:
	cd cluster/ansible && ansible-playbook bootstrap-fleet.yml

fleet-status:
	KUBECONFIG=$(KUBECONFIG_FILE) kubectl get gitrepo,bundles,bundledeployments -A
	KUBECONFIG=$(KUBECONFIG_FILE) kubectl get pods -A

install: vm-create cluster-create fleet-bootstrap

validate:
	@echo "------------------------- Nodes ----------------------------"
	KUBECONFIG=$(KUBECONFIG_FILE) kubectl get nodes -o wide
	@echo "------------------------- Pods -----------------------------"
	KUBECONFIG=$(KUBECONFIG_FILE) kubectl get pods -A
	@echo "------------------------- Fleet ----------------------------"
	KUBECONFIG=$(KUBECONFIG_FILE) kubectl get gitrepo,bundles,bundledeployments -A
	@echo "------------------------- Helm -----------------------------"
	KUBECONFIG=$(KUBECONFIG_FILE) helm list -A
	@echo "------------------------- Certificates ---------------------"
	KUBECONFIG=$(KUBECONFIG_FILE) kubectl get certificate -A
	@echo "------------------------- StorageClass ---------------------"
	KUBECONFIG=$(KUBECONFIG_FILE) kubectl get storageclass
	@echo "------------------------- PVC ------------------------------"
	KUBECONFIG=$(KUBECONFIG_FILE) kubectl get pvc -A
	@echo "------------------------- PV -------------------------------"
	KUBECONFIG=$(KUBECONFIG_FILE) kubectl get pv
	@echo "------------------------- Services -------------------------"
	KUBECONFIG=$(KUBECONFIG_FILE) kubectl get svc -A
	@echo "------------------------- Ingress --------------------------"
	KUBECONFIG=$(KUBECONFIG_FILE) kubectl get ingress -A
	@echo "------------------------- Keycloak HTTPS -------------------"
	curl -vk https://keycloak.local.example

cleanup: cluster-delete vm-delete