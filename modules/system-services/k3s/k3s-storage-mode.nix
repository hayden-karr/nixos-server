{ lib, ... }:

# K3s Storage Options
# Declares storage configuration options for k3s deployments
# Values set in config.nix, declarations here define what's valid

{
  options.container-backend.k3s.storageMode = lib.mkOption {
    type = lib.types.enum [ "hostPath" "pvc" ];
    default = "hostPath";
    description = ''
      Storage mode for k3s deployments.

      - "hostPath": Direct host filesystem mounts
        - Simple, no overhead
        - Shares data with podman containers
        - Single-node only (cannot add worker nodes)

      - "pvc": PersistentVolumeClaims with StorageClass
        - Enables multi-node clusters
        - Requires network storage (NFS/Ceph/Longhorn)
        - Does NOT share data with podman (separate storage)

      Default: "hostPath" for single-node simplicity and podman compatibility
    '';
  };

  options.container-backend.k3s.storageClassName = lib.mkOption {
    type = lib.types.str;
    default = "local-path";
    description = ''
      StorageClass name when using PVC mode.

      Common options:
      - "local-path": k3s default (still single-node, but uses PVC abstraction)
      - "nfs-client": NFS-based storage (requires nfs-subdir-external-provisioner)
      - "longhorn": Distributed block storage for multi-node
      - Cloud providers: "aws-ebs", "gce-pd", "azure-disk"

      Only relevant when storageMode = "pvc"
    '';
  };
}
