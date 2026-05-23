.PHONY: vm-create vm-delete cluster-create cluster-delete fleet-bootstrap fleet-status install validate cleanup

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
	KUBECONFIG=cluster/ansible/k3s.yaml kubectl get gitrepo,bundles,bundledeployments -A
	KUBECONFIG=cluster/ansible/k3s.yaml kubectl get pods -A

install: vm-create cluster-create fleet-bootstrap

validate:
	KUBECONFIG=cluster/ansible/k3s.yaml kubectl get nodes -o wide
	KUBECONFIG=cluster/ansible/k3s.yaml kubectl get pods -A
	KUBECONFIG=cluster/ansible/k3s.yaml kubectl get gitrepo,bundles,bundledeployments -A

cleanup: cluster-delete vm-delete