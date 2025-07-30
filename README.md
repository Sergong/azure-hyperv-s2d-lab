
---

## 🧰 Azure Hyper-V S2D Lab (Nested Virtualization)

Simulates a 2-node Hyper-V cluster with **Storage Spaces Direct (S2D)** using **nested virtualization** in Azure. Ideal for testing clustering, failover, and VM provisioning workflows.

---

### 📐 Architecture Overview

```mermaid
graph TD
  A[Azure VM: hyperv-node-0] -->|Nested Hyper-V| B[Test VMs]
  C[Azure VM: hyperv-node-1] -->|Nested Hyper-V| D[Test VMs]
  A --> E[Internal VNet]
  C --> E
  A --> F[Storage Pool (S2D)]
  C --> F
  F --> G[Cluster: S2DCluster]
```

---

### 🚀 Deployment Steps

1. **Clone the repo**
   ```bash
   git clone https://github.com/YOUR_USERNAME/azure-hyperv-s2d-lab.git
   cd azure-hyperv-s2d-lab
   ```

2. **Customize variables**
   - Edit `main.tf` to adjust region, VM size, credentials
   - Ensure `bootstrap.ps1` is tailored to your cluster name and IPs

3. **Deploy with Terraform**
   ```bash
   terraform init
   terraform apply
   ```

4. **Post-deployment**
   - Log into each VM
   - Verify Hyper-V and Failover Clustering are installed
   - Run `bootstrap.ps1` to configure S2D and create the cluster

---

### 🧪 Features

- Nested Hyper-V with internal switch
- Failover cluster with 2 nodes
- Storage Spaces Direct simulation using local disks
- Ready for test VM provisioning

---

### ⚠️ Gotchas

- Requires **Windows Server Datacenter edition**
- Azure VMs don’t support true shared storage — S2D simulates it
- Performance is limited — use for **lab/testing only**
- Ensure VM size supports nested virtualization (e.g., `Standard_D4s_v3`)

---

### 📄 Files

| File            | Purpose                                      |
|-----------------|----------------------------------------------|
| `main.tf`       | Terraform config for Azure infrastructure    |
| `bootstrap.ps1` | PowerShell script to configure Hyper-V + S2D |
| `README.md`     | This file — setup guide and usage notes      |

---

