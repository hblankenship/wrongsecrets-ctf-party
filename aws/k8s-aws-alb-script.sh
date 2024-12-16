#!/bin/bash
# set -o errexit
# set -o pipefail
# set -o nounset

source ../scripts/check-available-commands.sh
checkCommandsAvailable helm jq sed grep docker grep cat aws curl eksctl kubectl

if test -n "${AWS_REGION-}"; then
  echo "AWS_REGION is set to <$AWS_REGION>"
else
  AWS_REGION=eu-west-1
  echo "AWS_REGION is not set or empty, defaulting to ${AWS_REGION}"
fi

if test -n "${CLUSTERNAME-}"; then
  echo "CLUSTERNAME is set to <$CLUSTERNAME>"
else
  CLUSTERNAME=wrongsecrets-exercise-cluster
  echo "CLUSTERNAME is not set or empty, defaulting to ${CLUSTERNAME}"
fi

ACCOUNT_ID=$(aws sts get-caller-identity | jq '.Account' -r)
echo "ACCOUNT_ID=${ACCOUNT_ID}"

LBC_VERSION="v2.11.0"
echo "LBC_VERSION=$LBC_VERSION"

echo "setting up kubectl"

aws eks update-kubeconfig --region $AWS_REGION --name $CLUSTERNAME --kubeconfig ~/.kube/wrongsecrets

export KUBECONFIG=~/.kube/wrongsecrets

echo "applying aws-lbc with kubectl"

# kubectl apply -k "https://raw.githubusercontent.com/aws/eks-charts/master/stable/aws-load-balancer-controller/crds/crds.yaml"

kubectl get crd

echo "do helm eks application"
helm repo add eks https://aws.github.io/eks-charts
helm repo update

LOAD_BALANCER_CONTROLLER_ROLE_ARN="$(terraform output -raw load_balancer_controller_role_arn)"
kubectl create serviceaccount -n kube-system aws-load-balancer-controller
kubectl annotate serviceaccount -n kube-system --overwrite aws-load-balancer-controller eks.amazonaws.com/role-arn=${LOAD_BALANCER_CONTROLLER_ROLE_ARN}

echo "upgrade alb controller with helm"
helm upgrade -i aws-load-balancer-controller \
  eks/aws-load-balancer-controller \
  -n kube-system \
  --set clusterName=${CLUSTERNAME} \
  --set serviceAccount.create=false \
  --set serviceAccount.name=aws-load-balancer-controller \
  --set image.tag="${LBC_VERSION}" \
  --set region=${AWS_REGION} \
  --set image.repository=602401143452.dkr.ecr.${AWS_REGION}.amazonaws.com/amazon/aws-load-balancer-controller

# You may need to modify the account ID above if you're operating in af-south-1, ap-east-1, ap-southeast-3, cn-north and cn-northwest, eu-south-1, me-south-1, or the govcloud.
# See the full list of accounts per regions here: https://docs.aws.amazon.com/eks/latest/userguide/add-ons-images.html

echo "wait with rollout for 10 s"
sleep 10

echo "rollout status deployment"
kubectl -n kube-system rollout status deployment aws-load-balancer-controller

echo "wait after rollout for 10 s"
sleep 10

EKS_CLUSTER_VERSION=$(aws eks describe-cluster --name $CLUSTERNAME --region $AWS_REGION --query cluster.version --output text)

EXTERNAL_DNS_ROLE_ARN="$(terraform output -raw external_dns_role_arn)"
kubectl create serviceaccount -n kube-system external-dns
kubectl annotate serviceaccount -n kube-system --overwrite external-dns eks.amazonaws.com/role-arn=${EXTERNAL_DNS_ROLE_ARN}

echo "apply -f k8s/external-dns-*.yaml in 10 s"
sleep 10
kubectl apply -f k8s/external-dns-clusterrole.yaml
kubectl apply -f k8s/external-dns-clusterrolebinding.yaml
kubectl apply -f k8s/external-dns-deployment.yaml


echo "apply -f k8s/wrongsecrets-balancer-service.yml"
kubectl apply -f k8s/wrongsecrets-balancer-service.yml

export BALANCER_DOMAIN_NAME="$(terraform output -raw balancer_domain_name)"

envsubst <./k8s/wrongsecrets-balancer-ingress.yml.tpl >./k8s/wrongsecrets-balancer-ingress.yml

echo "apply -f k8s/wrongsecrets-balancer-ingress.yml"
kubectl apply -f k8s/wrongsecrets-balancer-ingress.yml

echo "apply -f k8s/ctfd-service.yaml"
kubectl apply -f k8s/ctfd-service.yaml

export CTFD_DOMAIN_NAME="$(terraform output -raw ctfd_domain_name)"
envsubst <./k8s/ctfd-ingress.yaml.tpl >./k8s/ctfd-ingress.yaml

echo "apply -f k8s/ctfd-ingress.yaml"
kubectl apply -f k8s/ctfd-ingress.yaml

echo "waiting 20 s for load balancer"
sleep 20
echo "Wrongsecrets ingress: http://$(kubectl get ingress wrongsecrets-balancer -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')"
echo "Wrongsecrets host: http://$(kubectl get ingress wrongsecrets-balancer -o jsonpath='{.spec.rules[0].host}')"
echo "ctfd ingress: http://$(kubectl get ingress -n ctfd ctfd -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')"
echo "ctfd host: http://$(kubectl get ingress -n ctfd ctfd -o jsonpath='{.spec.rules[0].host}')"

echo "Do not forget to cleanup afterwards! Run k8s-aws-alb-script-cleanup.sh"
