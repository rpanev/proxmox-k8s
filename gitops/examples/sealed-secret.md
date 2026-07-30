# Sealed Secret example — run on deploy host (controller must be installed):
#
#   kubectl create secret generic myapp-env \
#     --namespace myapp --from-literal=API_KEY=changeme --dry-run=client -o yaml \
#     | kubeseal --format yaml > gitops/apps/myapp/sealed-secret.yaml
#
# Commit sealed-secret.yaml; Argo CD applies it. Only the cluster can decrypt.
