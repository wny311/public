#!/bin/bash

set -euxo pipefail

export NODENAME=$1

case $NODENAME in
  master01|worker01)
	export RUNTIME=containerd
	;;
  worker02)
	export RUNTIME=docker
	;;
esac

function pkg_prepare_install {
  apt update -y
  until DEBIAN_FRONTEND=noninteractive apt install -y sshpass vim open-vm-tools  bash-completion netcat-openbsd iputils-ping gzip; do
  apt update -y
  done
}

function module_install {
  DEBIAN_FRONTEND=noninteractive apt -y install bridge-utils
  tee /etc/modules-load.d/br.conf >/dev/null<<-EOF
  	br_netfilter
EOF

  modprobe br_netfilter

  tee /etc/sysctl.d/k8s.conf >/dev/null<<-EOF
  	net.ipv4.ip_forward=1
EOF

  sysctl -p /etc/sysctl.d/k8s.conf
}

function runtime_install_containerd {
  apt install -y ca-certificates curl gnupg
  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://mirrors.aliyun.com/docker-ce/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  chmod a+r /etc/apt/keyrings/docker.gpg
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://mirrors.aliyun.com/docker-ce/linux/ubuntu "$(. /etc/os-release && echo "$VERSION_CODENAME")" stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
  
  apt update
  DEBIAN_FRONTEND=noninteractive apt install -y containerd.io

  containerd config default | sed -e '/SystemdCgroup/s+false+true+' | tee /etc/containerd/config.toml >/dev/null

  systemctl restart containerd
}

function runtime_install_docker {
  apt install -y ca-certificates curl gnupg
  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://mirrors.aliyun.com/docker-ce/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  chmod a+r /etc/apt/keyrings/docker.gpg
  echo 
    "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://mirrors.aliyun.com/docker-ce/linux/ubuntu \
    "$(. /etc/os-release && echo "$VERSION_CODENAME")" stable" | \
    sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
  
  apt update && DEBIAN_FRONTEND=noninteractive apt -y install docker-ce
  mkdir -p /etc/docker
  tee /etc/docker/daemon.json >/dev/null<<-EOF
	{
	  "exec-opts": ["native.cgroupdriver=systemd"],
	  "log-driver": "json-file",
	  "log-opts": {
	    "max-size": "100m",
	    "max-file": "10"
	  }
	}
EOF
  
  systemctl daemon-reload
  systemctl restart docker
  
  local CLI_ARCH=amd64
  local C_VERSION=$(curl -sL https://api.github.com/repos/Mirantis/cri-dockerd/releases/latest | awk '/tag_name/ {print $2}' | sed 's/[",v]//g')
  until curl -#LO ${CURL}https://github.com/Mirantis/cri-dockerd/releases/download/v$C_VERSION/cri-dockerd_$C_VERSION.3-0.ubuntu-jammy_$CLI_ARCH.deb; do
    sleep 1
  done
  dpkg -i cri-dockerd_${C_VERSION}.3-0.ubuntu-jammy_${CLI_ARCH}.deb

  sed -i '/ExecStart/s+$+ --network-plugin=cni+' /lib/systemd/system/cri-docker.service
	
  systemctl daemon-reload
  systemctl restart cri-docker
}

function k8s_install {
  apt update && apt install -y apt-transport-https
  curl -fsSL https://mirrors.aliyun.com/kubernetes-new/core/stable/v1.34/deb/Release.key | gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
  echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://mirrors.aliyun.com/kubernetes-new/core/stable/v1.34/deb/ /" | tee /etc/apt/sources.list.d/kubernetes.list
  apt update
  DEBIAN_FRONTEND=noninteractive apt install -y kubelet=1.34.0-1.1 kubeadm=1.34.0-1.1 kubectl=1.34.0-1.1
  apt-mark hold kubelet kubeadm kubectl
}

function kubeadm_tab {
	[ ! -d /root/.kube ] && mkdir /root/.kube
	source <(kubeadm completion bash)

	kubeadm completion bash | tee /etc/bash_completion.d/kubeadm >/dev/null
}

function client_tab {
	source <(kubectl completion bash)
	kubectl completion bash | tee /etc/bash_completion.d/kubectl >/dev/null
}

function pause_image_version {
  export PI_VERSION=$(kubeadm config images list --kubernetes-version=1.34.0 | awk -F: '/pause/ {print $2}')
  
  case ${RUNTIME} in
  	containerd)
  		sed -ie "/sandbox_image/s+pause.*+pause:${PI_VERSION}\"+" /etc/containerd/config.toml
  		systemctl restart containerd
  		;;
  	docker)
  		sed -i "/ExecStart/s+$+ --pod-infra-container-image=registry.k8s.io/pause:${PI_VERSION}+" /lib/systemd/system/cri-docker.service
  		systemctl daemon-reload
  		systemctl restart cri-docker
  		;;
  esac
}

function crictl_config {
  case $RUNTIME in
  	containerd)
  	  crictl config \
  	  --set runtime-endpoint=unix:///run/containerd/containerd.sock \
  	  --set image-endpoint=unix:///run/containerd/containerd.sock \
  	  --set timeout=10
  	  ;;
  	docker)
  	  crictl config \
  	  --set runtime-endpoint=unix:///var/run/cri-dockerd.sock \
  	  --set image-endpoint=unix:///var/run/cri-dockerd.sock \
  	  --set timeout=10
  	  ;;
  esac
     
  source <(crictl completion bash)
  crictl completion bash | tee /etc/bash_completion.d/crictl >/dev/null
}

function kubeadm_init {
  kubeadm config images pull --kubernetes-version 1.34.0 
  local CONTROL_IP=$(hostname -I)
  kubeadm init \
  --kubernetes-version 1.34.0 \
  --apiserver-advertise-address=${CONTROL_IP} \
  --pod-network-cidr=10.244.1.0/16 \
  --service-cidr=10.96.1.0/16 \
  --node-name=$(hostname -s)
}

function client_config {
	echo "export KUBECONFIG=/etc/kubernetes/admin.conf" | tee -a /root/.bashrc
	export KUBECONFIG=/etc/kubernetes/admin.conf
}

function kubeadm_join {
  until nc -w 2 master01 6443; do
  	sleep 2
  done
     
  case ${RUNTIME} in
  	containerd)
  		sudo $(ssh -o StrictHostKeyChecking=no master01 kubeadm token create --print-join-command)
  		;;
  	docker)
  		sudo $(ssh -o StrictHostKeyChecking=no master01 kubeadm token create --print-join-command) --cri-socket=unix:///var/run/cri-dockerd.sock
  		;;
  esac
}

function cni_cilium_install {
  local CLI_ARCH=amd64
  local CILIUM_CLI_VERSION=$(curl -sL https://api.github.com/repos/cilium/cilium-cli/releases/latest | awk '/tag_name/ {print $2}' | sed 's/[",v]//g')
  until curl -s -L --fail --remote-name-all https://github.com/cilium/cilium-cli/releases/download/v${CILIUM_CLI_VERSION}/cilium-linux-${CLI_ARCH}.tar.gz; do
	sleep 1
  done
  
  tar xvf cilium-linux-${CLI_ARCH}.tar.gz -C /usr/local/bin
  rm cilium-linux-${CLI_ARCH}.tar.gz

  cilium install --wait

  cilium status

  source <(cilium completion bash)
  cilium completion bash | tee /etc/bash_completion.d/cilium >/dev/null
}

function hongkong {
	kubectl taint node k8s-master node-role.kubernetes.io/control-plane:NoSchedule-
}

#main 
touch /tmp/$(date +%m%d-%H%M).begin

pkg_prepare_install

module_install
	
case $RUNTIME in
  containerd)
	runtime_install_containerd
	;;
  docker)
	runtime_install_docker
	;;
esac

k8s_install

kubeadm_tab

pause_image_version

crictl_config

case "$(hostname -s)" in
	*master*)
		kubeadm_init
		client_config
		cni_cilium_install	
		client_tab
		hongkong
		;;
	*worker*)
		kubeadm_join
		mkdir -p /root/.kube && rsync master01:/etc/kubernetes/admin.conf /root/.kube/config
		;;
esac
touch /tmp/$(date +%m%d-%H%M).end
