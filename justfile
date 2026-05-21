pwd := source_dir()
export KUBECONFIG := pwd + "/kubeconfig"

docker:
  docker compose up

k8s:
  minikube start
  terraform apply -auto-approve
  kubectl port-forward --kubeconfig=kubeconfig -n traefik deployment/traefik 8080:8000 8443:8443 &

k8s-clean:
  minikube delete
