# Kubernetes Post-Startup Cluster Setup

`cluster-setup.sh` is a post-startup shell script designed to bootstrap and configure essential services inside a newly provisioned Kubernetes cluster. The script supports multiple execution profiles (e.g., `full`, `kind`, `vanilla`, `minimal`) to selectively install CNI (Calico), metrics-server, MetalLB (L2 load balancer), and Istio service mesh, while handling node labeling and network address pooling dynamically.

## Features

- **Profile-Driven Installation**: Install specific sets of cluster components using defined profiles (`full`, `kind`, `vanilla`, `minimal`).
- **Pre-flight Checks**: Verifies that the required binaries exist in the command path and that a valid Kubernetes context is active.
- **Automatic Node Labeling**: Labels non-control-plane worker nodes with the standard worker role (`node-role.kubernetes.io/worker=`).
- **Dynamic IP Pool Matching**: Automatically reads each worker node's podCIDR block to create Calico IPPool CRDs, replacing default pools for accurate routing.
- **Automated Virtual IP Management**: Auto-detects the host subnet or utilizes user-defined virtual IPs to configure MetalLB's IPAddressPool and L2Advertisement.
- **Insecure Kubelet TLS Support**: Deploys metrics-server with options configured for testing environments.
- **Self-Cleaning**: Cleans up all temporary manifest files from `/tmp/cluster-setup` on exit.

---

## Requirements

Before running the script, ensure you have the following command-line tools installed and available in your `PATH`:

- **kubectl**: CLI for communicating with the Kubernetes API.
- **helm**: Package manager for deploying charts (metrics-server, MetalLB).
- **istioctl**: CLI for installing and managing Istio service mesh.

You must also have a configured and active Kubernetes context. Verify this by running:
```bash
kubectl config current-context
```

---

## Environment Variables

The script behaves dynamically based on the following environment variables:

| Variable | Default Value | Description |
| :--- | :--- | :--- |
| `CALICO_VERSION` | `v3.31.3` | The version tag of Calico to fetch and install from the Project Calico repository. |
| `METALLB_VIP_RANGE` | *Auto-selected* | The range of virtual IP addresses assigned to the MetalLB L2 load balancer. If not set, it is dynamically computed using the first node's IP address (e.g., `X.Y.Z.200-X.Y.Z.250`). |

---

## Profiles

The script provides four deployment profiles, tailored for different cluster runtime contexts:

| Profile | Calico CNI | Metrics Server | MetalLB | Istio Service Mesh | Target Use Case |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **`full`** | ✔️ | ✔️ | ✔️ | ✔️ | Standard bare-metal / VM-based multi-node cluster. |
| **`kind`** | ❌ | ✔️ | ✔️ | ✔️ | Kind (Kubernetes in Docker) local clusters. |
| **`vanilla`** | ✔️ | ✔️ | ✔️ | ❌ | Clusters requiring routing and monitoring but no mesh. |
| **`minimal`** | ❌ | ✔️ | ✔️ | ❌ | Basic local development/testing setups. |

---

## Usage

Run the script by providing the `--profile` flag and one of the supported values:

```bash
./cluster-setup.sh --profile [ full | kind | vanilla | minimal ]
```

### Examples

#### 1. Full Bootstrap (Production / Staging VMs)
Install and configure Calico, metrics-server, MetalLB, and Istio:
```bash
./cluster-setup.sh --profile full
```

#### 2. Local Kind Cluster Setup
Set up a Kind cluster, skipping Calico installation (since Kind provides its own CNI/networking) but installing Istio:
```bash
./cluster-setup.sh --profile kind
```

#### 3. Custom MetalLB IP Range
Override the automatically detected MetalLB VIP range:
```bash
METALLB_VIP_RANGE="192.168.1.100-192.168.1.150" ./cluster-setup.sh --profile vanilla
```

#### 4. Custom Calico Version
Install a specific Calico release:
```bash
CALICO_VERSION="v3.26.1" ./cluster-setup.sh --profile full
```

---

## Setup Execution Flow

1. **Initialization**: Creates a temporary directory at `/tmp/cluster-setup` to store working manifest files.
2. **Pre-flight Checks**: Runs `check_tools` and `check_context` to validate dependencies and active cluster connection.
3. **Worker Labeling**: Inspects cluster nodes, filtering out control-plane nodes, and applies the `node-role.kubernetes.io/worker=` label to unlabeled nodes.
4. **Component Deployment**: Based on the profile:
   - **Calico**: Downloads the official manifest, applies it, waits for the controller to rollout, generates tailored `IPPool` custom resources per node based on their CIDR, and deletes the default IPv4 pool.
   - **Metrics Server**: Configures Helm repository, installs metrics-server with `--kubelet-insecure-tls` argument enabled.
   - **MetalLB**: Adds Helm repository, installs MetalLB, and configures L2 advertisement with the computed or specified IP range.
   - **Istio**: Invokes `istioctl` to deploy the `default` profile inside the `istio-system` namespace.
5. **Clean up**: Deletes the temporary working directory at `/tmp/cluster-setup`.
