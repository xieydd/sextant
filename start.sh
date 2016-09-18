#!/bin/sh
# FIXME: DEFAULT_IPV4 is the last ip
DEFAULT_IPV4=`grep "bootstrapper:" /bsroot/config/cluster-desc.yml | awk '{print $2}' | sed 's/ //g'`
BOOTATRAPPER_DOMAIN=`grep "dockerdomain:" /bsroot/config/cluster-desc.yml | awk '{print $2}' | sed 's/"//g' | sed 's/ //g'`
MASTER_HOSTNAME=`grep "kube_master: y" /bsroot/config/cluster-desc.yml -B 5 |grep "mac" | awk '{print $3}' | sed 's/"//g'`
# update install.sh domain
sed -i 's/<HTTP_ADDR>/'"$DEFAULT_IPV4"':8081/g' /bsroot/html/static/cloud-configs/install.sh
# start dnsmasq
dnsmasq --log-facility=- -q --conf-file=/bsroot/config/dnsmasq.conf
# run addons
addons -cluster-desc-file /bsroot/config/cluster-desc.yml \
  -template-file /bsroot/config/ingress.template \
  -config-file /bsroot/html/static/ingress.yaml &

addons -cluster-desc-file /bsroot/config/cluster-desc.yml \
  -template-file /bsroot/config/skydns.template \
  -config-file /bsroot/html/static/skydns.yaml &

# start cloud-config-server
cloud-config-server -addr ":8081" \
  -dir /bsroot/html/static \
  -cc-template-file /bsroot/config/cloud-config.template \
  -cc-template-url "" \
  -cluster-desc-file /bsroot/config/cluster-desc.yml \
  -cluster-desc-url "" \
  -ca-crt /bsroot/tls/ca.pem \
  -ca-key /bsroot/tls/ca-key.pem \
  -ingress-template-file /bsroot/config/ingress.template \
  -skydns-template-file /bsroot/config/skydns.template &
# start registry
registry serve /bsroot/config/registry.yml &
sleep 2
# push k8s images to registry from bsroot
DOCKER_IMAGES=('typhoon1986/hyperkube-amd64:v1.2.0' \
  'typhoon1986/pause:2.0' \
  'typhoon1986/flannel:0.5.5' \
  'yancey1989/nginx-ingress-controller:0.8.3' \
  'yancey1989/kube2sky:1.14' \
  'typhoon1986/exechealthz:1.0' \
  'typhoon1986/skydns:latest');
len=${#DOCKER_IMAGES[@]}
for ((i=0;i<len;i++)); do
  DOCKER_IMAGE=${DOCKER_IMAGES[i]}
  DOCKER_TAR_FILE=`echo /bsroot/${DOCKER_IMAGE}.tar | sed "s/:/_/g" |awk -F'/' '{print $2}'`
  DOCKER_TAG_NAME=`echo $BOOTATRAPPER_DOMAIN:5000/${DOCKER_IMAGE} | awk -F'/' '{print $1"/"$3}'`
  docker load < $DOCKER_TAR_FILE
  docker tag $DOCKER_IMAGE $DOCKER_TAG_NAME
  docker push $DOCKER_TAG_NAME
done
# config kubectl
kubectl set-cluster config set-cluster k8sp --server http://$MASTER_HOSTNAME:8080
kubectl config set-context k8sp --cluster=k8sp
kubectl config use-context k8sp
kubectl create -f /bsroot/html/static/ingress.yaml
kubectl create -f /bsroot/html/static/skydns.yaml
wait
