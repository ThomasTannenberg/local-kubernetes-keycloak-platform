.PHONY: vm-create vm-delete cluster-create cluster-delete install validate cleanup

vm-create:
	cd cluster/libvirt && ./00-bootstrap.sh
	cd cluster/libvirt && ./01-deploy-cluster-cloudimg.sh

vm-delete:
	cd cluster/libvirt && ./99-cleanup.sh

cluster-create:
	cd cluster/ansible && ansible-playbook site.yml

cluster-delete:
	cd cluster/ansible && ansible-playbook uninstall.yml

install:
	./scripts/install-all.sh

validate:
	./scripts/validate.sh

cleanup: cluster-delete
