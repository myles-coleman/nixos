{ config, pkgs, lib, ... }:

{
  imports = [
    ./k3s-common.nix
    ./k3s-token-secrets.nix
  ];

  environment.etc."rancher/k3s/server/manifests/kube-vip.yaml".text = ''
    apiVersion: v1
    kind: Pod
    metadata:
      name: kube-vip
      namespace: kube-system
    spec:
      containers:
      - name: kube-vip
        image: ghcr.io/kube-vip/kube-vip@sha256:a48dc8d85c7d36876dcc8c0661ac225603936065e51e2e3a92978f036877dcb2
        args: ["manager"]
        env:
        - name: vip_arp
          value: "true"
        - name: vip_interface
          value: "eth0"
        - name: port
          value: "6443"
        - name: vip_address
          value: "10.0.0.200"
        - name: vip_cidr
          value: "32"
        - name: cp_enable
          value: "true"
        - name: cp_namespace
          value: "kube-system"
        - name: svc_enable
          value: "false"
        - name: vip_leaderelection
          value: "true"
        - name: vip_leaseduration
          value: "15"
        - name: vip_renewdeadline
          value: "10"
        - name: vip_retryperiod
          value: "2"
        securityContext:
          capabilities:
            add: ["NET_ADMIN", "NET_RAW"]
        volumeMounts:
        - mountPath: /etc/kubernetes/admin.conf
          name: kubeconfig
      hostNetwork: true
      volumes:
      - name: kubeconfig
        hostPath:
          path: /etc/rancher/k3s/k3s.yaml
  '';

  services.k3s = {
    enable = true;
    role = "server";
    tokenFile = "/etc/rancher/k3s/token";
    extraFlags = toString [
      "--flannel-iface=eth0"
      "--tls-san 10.0.0.200"
      "--disable servicelb"
      "--disable traefik"
      "--write-kubeconfig-mode 644"
    ];
  };
  
  systemd.services.k3s-kubeconfig-copy = {
    description = "Copy k3s kubeconfig to user directory";
    after = [ "k3s.service" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      mkdir -p /home/pi/.kube
      cp /etc/rancher/k3s/k3s.yaml /home/pi/.kube/config
      chown -R pi:users /home/pi/.kube
      chmod 600 /home/pi/.kube/config
    '';
  };
}
