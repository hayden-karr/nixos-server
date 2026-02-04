{ config, lib, pkgs, osConfig, ... }:

# ArgoCD - GitOps Continuous Delivery for Kubernetes (Rootless)
# Web UI accessible via NodePort 30443
# Manifests managed in git at k8s/ directory

let
  k3sDataDir = "${config.home.homeDirectory}/k3s";
  kubeconfigPath = "${k3sDataDir}/k3s.yaml";
  cfg = osConfig.serverConfig.container-backend.k3s.gitops;

  # Determine which repo URL to use based on provider
  repoURL = if cfg.gitProvider == "gitea" then
    cfg.gitea.internalURL
  else
    cfg.github.repoURL;

  targetRevision = if cfg.gitProvider == "gitea" then
    cfg.gitea.targetRevision
  else
    cfg.github.targetRevision;

  gitProviderName = if cfg.gitProvider == "gitea" then "Gitea" else "GitHub";
in {
  config = lib.mkIf (osConfig.serverConfig.container-backend.backend == "k3s") {

    # Install ArgoCD via user systemd service
    systemd.user.services.install-argocd = {
      Unit = {
        Description = "Install ArgoCD GitOps platform (rootless)";
        After = [ "k3s-server.service" ];
      };

      Service = {
        Type = "oneshot";
        RemainAfterExit = true;
        Environment = "KUBECONFIG=${kubeconfigPath}";

        ExecStart = pkgs.writeShellScript "install-argocd" ''
          # Wait for K3s API to be ready
          echo "Waiting for K3s API..."
          until ${pkgs.kubectl}/bin/kubectl get nodes &>/dev/null; do
            ${pkgs.coreutils}/bin/sleep 2
          done

          # Create argocd namespace
          ${pkgs.kubectl}/bin/kubectl create namespace argocd 2>/dev/null || true

          # Install ArgoCD (latest stable release)
          ${pkgs.kubectl}/bin/kubectl apply -n argocd -f \
            https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml || true

          # Wait for ArgoCD server to be created
          ${pkgs.coreutils}/bin/sleep 5

          # Patch ArgoCD server service to use LoadBalancer (rootless k3s binds to host)
          # Port 443 will be accessible at host:10443 (443 + 10000 offset for ports <1024)
          ${pkgs.kubectl}/bin/kubectl patch svc argocd-server -n argocd \
            -p '{"spec":{"type":"LoadBalancer","ports":[{"name":"https","port":443,"targetPort":8080}]}}' || true

          echo "ArgoCD installed successfully"
        '';
      };

      Install = { WantedBy = [ "default.target" ]; };
    };

    # Configure Git repository credentials (if configured)
    systemd.user.services.argocd-configure-repo = lib.mkIf
      (cfg.enable && (cfg.sshKeyPath != null || cfg.passwordFile != null)) {
        Unit = {
          Description = "Configure ArgoCD Git Repository Credentials";
          After = [ "install-argocd.service" ];
        };

        Service = {
          Type = "oneshot";
          RemainAfterExit = true;
          Environment = "KUBECONFIG=${kubeconfigPath}";

          ExecStart = let useSSH = cfg.sshKeyPath != null;
          in pkgs.writeShellScript "configure-argocd-repo" ''
            # Wait for ArgoCD to be ready (with timeout)
            TIMEOUT=300  # 5 minutes
            ELAPSED=0
            until ${pkgs.kubectl}/bin/kubectl get namespace argocd &>/dev/null; do
              if [ $ELAPSED -ge $TIMEOUT ]; then
                echo "Timeout waiting for ArgoCD namespace"
                exit 1
              fi
              echo "Waiting for ArgoCD namespace... ($ELAPSED/$TIMEOUT seconds)"
              ${pkgs.coreutils}/bin/sleep 5
              ELAPSED=$((ELAPSED + 5))
            done

            echo "Configuring ArgoCD repository: ${repoURL}"

            ${if useSSH then ''
              # SSH Key Authentication
              echo "Using SSH key authentication from ${cfg.sshKeyPath}"

              ${pkgs.kubectl}/bin/kubectl apply -f - <<EOF
              apiVersion: v1
              kind: Secret
              metadata:
                name: repo-credentials
                namespace: argocd
                labels:
                  argocd.argoproj.io/secret-type: repository
              stringData:
                type: git
                url: ${repoURL}
                sshPrivateKey: |
              $(${pkgs.coreutils}/bin/cat ${cfg.sshKeyPath} | ${pkgs.gnused}/bin/sed 's/^/    /')
              EOF
            '' else ''
              # HTTPS Authentication
              echo "Using HTTPS authentication with username: ${cfg.username}"

              PASSWORD=$(${pkgs.coreutils}/bin/cat ${cfg.passwordFile})

              ${pkgs.kubectl}/bin/kubectl apply -f - <<EOF
              apiVersion: v1
              kind: Secret
              metadata:
                name: repo-credentials
                namespace: argocd
                labels:
                  argocd.argoproj.io/secret-type: repository
              stringData:
                type: git
                url: ${repoURL}
                username: ${cfg.username}
                password: $PASSWORD
              EOF
            ''}

            echo "✓ Repository credentials configured"
          '';
        };

        Install = { WantedBy = [ "default.target" ]; };
      };

    # Helper commands for ArgoCD and immich-friend stack
    home.packages = [
      # Get ArgoCD admin password
      (pkgs.writeShellScriptBin "argocd-password" ''
        export KUBECONFIG=${kubeconfigPath}
        echo "ArgoCD admin password:"
        ${pkgs.kubectl}/bin/kubectl -n argocd get secret argocd-initial-admin-secret \
          -o jsonpath="{.data.password}" 2>/dev/null | ${pkgs.coreutils}/bin/base64 -d
        echo ""
      '')

      # Setup ArgoCD Applications for immich-friend stack
      (pkgs.writeShellScriptBin "immich-friend-argocd-setup" ''
        export KUBECONFIG=${kubeconfigPath}

        echo "╔════════════════════════════════════════════════════════════════╗"
        echo "║         ArgoCD GitOps Setup - Immich Friend Stack            ║"
        echo "╚════════════════════════════════════════════════════════════════╝"
        echo ""
        echo "Git Provider: ${gitProviderName}"
        echo "Repository:   ${repoURL}"
        echo "Branch:       ${targetRevision}"
        echo ""

        # Wait for ArgoCD to be ready
        echo "Waiting for ArgoCD to be ready..."
        until ${pkgs.kubectl}/bin/kubectl get namespace argocd &>/dev/null; do
          echo "  Waiting for ArgoCD namespace..."
          ${pkgs.coreutils}/bin/sleep 2
        done

        until ${pkgs.kubectl}/bin/kubectl get deployment argocd-server -n argocd &>/dev/null; do
          echo "  Waiting for ArgoCD deployment..."
          ${pkgs.coreutils}/bin/sleep 2
        done

        echo "✓ ArgoCD is ready"
        echo ""

        # Create ArgoCD Application for ingress-nginx
        echo "Creating ingress-nginx application..."
        ${pkgs.kubectl}/bin/kubectl apply -f - <<EOF
        apiVersion: argoproj.io/v1alpha1
        kind: Application
        metadata:
          name: ingress-nginx
          namespace: argocd
          finalizers:
          - resources-finalizer.argocd.argoproj.io
        spec:
          project: default
          source:
            repoURL: ${repoURL}
            targetRevision: ${targetRevision}
            path: k8s/ingress-nginx
          destination:
            server: https://kubernetes.default.svc
            namespace: ingress-nginx
          syncPolicy:
            automated:
              prune: true
              selfHeal: true
            syncOptions:
            - CreateNamespace=true
            retry:
              limit: 5
              backoff:
                duration: 5s
                factor: 2
                maxDuration: 3m
        EOF

        # Create ArgoCD Application for immich-friend
        echo "Creating immich-friend application..."
        ${pkgs.kubectl}/bin/kubectl apply -f - <<EOF
        apiVersion: argoproj.io/v1alpha1
        kind: Application
        metadata:
          name: immich-friend
          namespace: argocd
          finalizers:
          - resources-finalizer.argocd.argoproj.io
        spec:
          project: default
          source:
            repoURL: ${repoURL}
            targetRevision: ${targetRevision}
            path: k8s/immich-friend
          destination:
            server: https://kubernetes.default.svc
            namespace: immich-friend
          syncPolicy:
            automated:
              prune: true
              selfHeal: true
            syncOptions:
            - CreateNamespace=true
            retry:
              limit: 5
              backoff:
                duration: 5s
                factor: 2
                maxDuration: 3m
        EOF

        echo ""
        echo "╔════════════════════════════════════════════════════════════════╗"
        echo "║                  ✓ Setup Complete!                            ║"
        echo "╚════════════════════════════════════════════════════════════════╝"
        echo ""
        echo "ArgoCD Applications created for GitOps workflow."
        echo ""
        echo "Access ArgoCD Dashboard:"
        echo "  • Get password: argocd-password"
        echo "  • URL: http://localhost:30443"
        echo ""
      '')

      # Quick status check for immich-friend stack
      (pkgs.writeShellScriptBin "immich-friend-status" ''
        export KUBECONFIG=${kubeconfigPath}

        echo "╔════════════════════════════════════════════════════════════════╗"
        echo "║          Immich Friend Deployment Status                     ║"
        echo "╚════════════════════════════════════════════════════════════════╝"
        echo ""

        echo "ArgoCD Applications:"
        echo "───────────────────────────────────────────────────────────────"
        ${pkgs.kubectl}/bin/kubectl get application -n argocd 2>/dev/null || echo "  ArgoCD not found"
        echo ""

        echo "Immich-Friend Pods:"
        echo "───────────────────────────────────────────────────────────────"
        ${pkgs.kubectl}/bin/kubectl get pods -n immich-friend 2>/dev/null || echo "  Namespace not found"
        echo ""

        echo "Ingress-Nginx Pods:"
        echo "───────────────────────────────────────────────────────────────"
        ${pkgs.kubectl}/bin/kubectl get pods -n ingress-nginx 2>/dev/null || echo "  Namespace not found"
        echo ""
      '')

      # Show logs for immich-friend pods
      (pkgs.writeShellScriptBin "immich-friend-logs" ''
        export KUBECONFIG=${kubeconfigPath}

        if [ $# -eq 0 ]; then
          echo "Usage: immich-friend-logs <pod-name>"
          echo ""
          echo "Available pods:"
          ${pkgs.kubectl}/bin/kubectl get pods -n immich-friend --no-headers 2>/dev/null | awk '{print "  "$1}'
          exit 1
        fi

        ${pkgs.kubectl}/bin/kubectl logs -n immich-friend "$1" --follow
      '')
    ];
  };
}
