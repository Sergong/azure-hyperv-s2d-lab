# Terraform Race Condition Prevention Guide for Azure Deployments

## Overview
This document explains how to prevent race conditions in Azure Terraform deployments, specifically for VM extensions and other concurrent operations that can conflict.

## What Caused the Original Race Condition

The original issue occurred because:
1. **Simultaneous Operations**: Two VM extensions were being created simultaneously using `count`
2. **Azure API Limits**: Azure has throttling limits for concurrent VM operations
3. **Resource Contention**: Multiple operations competing for the same Azure API endpoints
4. **Timing Issues**: Extensions starting before prerequisite resources were fully ready

## Prevention Strategies Implemented

### 1. Sequential Execution Pattern

**Before (Race Condition Prone):**
```hcl
resource "azurerm_virtual_machine_extension" "bootstrap" {
  count = 2  # Creates both simultaneously
  # ... configuration
}
```

**After (Sequential Execution):**
```hcl
# Primary node first
resource "azurerm_virtual_machine_extension" "bootstrap_node_0" {
  # ... configuration for node 0
}

# Secondary node waits for primary
resource "azurerm_virtual_machine_extension" "bootstrap_node_1" {
  # ... configuration for node 1
  depends_on = [azurerm_virtual_machine_extension.bootstrap_node_0]
}
```

### 2. Explicit Dependency Chains

Ensure proper resource ordering:
```hcl
depends_on = [
  azurerm_windows_virtual_machine.hyperv_node,           # VMs ready
  azurerm_virtual_machine_data_disk_attachment.s2d_disk_attachment,  # Disks attached
  azurerm_storage_blob.bootstrap_script,                 # Scripts uploaded
  azurerm_storage_blob.s2d_script
]
```

### 3. Resource Naming Strategy

**Better Resource Names:**
- `bootstrap_node_0` / `bootstrap_node_1` instead of `bootstrap[0]` / `bootstrap[1]`
- Explicit, descriptive names for easier targeting and troubleshooting
- No array indices that can cause confusion during imports/exports

### 4. Alternative: for_each Instead of count

Using `for_each` provides better resource management:
```hcl
locals {
  vm_nodes = {
    "hyperv-node-0" = { is_primary = true }
    "hyperv-node-1" = { is_primary = false }
  }
}

resource "azurerm_virtual_machine_extension" "bootstrap_primary" {
  # Primary node configuration
}

resource "azurerm_virtual_machine_extension" "bootstrap_secondary" {
  depends_on = [azurerm_virtual_machine_extension.bootstrap_primary]
}
```

### 5. Explicit Timeouts

Add timeouts for long-running operations:
```hcl
resource "azurerm_virtual_machine_extension" "bootstrap_node_0" {
  # ... configuration
  
  timeouts {
    create = "30m"
    update = "30m" 
    delete = "30m"
  }
}
```

## File Versions Available

### 1. main.tf (Current - Sequential Approach)
- Uses separate `bootstrap_node_0` and `bootstrap_node_1` resources
- Sequential execution with explicit dependencies
- Most straightforward approach

### 2. main-foreach-version.tf (Alternative - for_each Approach) 
- Uses `for_each` with explicit resource maps
- Better for larger deployments with many nodes
- More complex but more scalable

## Best Practices Summary

### ✅ Do This:
1. **Split concurrent resources** into separate named resources
2. **Use explicit `depends_on`** to control execution order
3. **Add timeouts** for long-running operations
4. **Test dependency chains** before production deployments
5. **Use descriptive resource names** instead of indexed arrays
6. **Validate all prerequisites** are ready before dependent resources

### ❌ Avoid This:
1. **Don't use `count`** for resources that might have API conflicts
2. **Don't assume ordering** - always use explicit dependencies
3. **Don't skip validation** of resource readiness
4. **Don't ignore Azure API throttling limits**

## Recovery from Race Conditions

If you encounter a race condition:

1. **Import Missing Resources:**
   ```bash
   terraform import 'azurerm_virtual_machine_extension.bootstrap[1]' '/subscriptions/.../extensions/bootstrap-extension'
   ```

2. **Use Targeted Apply:**
   ```bash
   terraform apply -target='azurerm_virtual_machine_extension.bootstrap_node_1'
   ```

3. **Check Resource State:**
   ```bash
   terraform show
   terraform state list
   ```

## Monitoring and Validation

### Check Extension Status:
```bash
# Via Azure CLI
az vm extension list --vm-name hyperv-node-0 --resource-group hyperv-nested-rg

# Via PowerShell on the VM
Get-AzVMExtension -ResourceGroupName hyperv-nested-rg -VMName hyperv-node-0
```

### Terraform State Validation:
```bash
terraform plan    # Should show "No changes"
terraform validate
terraform fmt -check
```

## Performance Considerations

1. **Sequential execution** is slower but more reliable
2. **Parallel execution** is faster but prone to conflicts
3. **Hybrid approach**: Parallelize non-conflicting resources, sequence conflicting ones
4. **Azure quotas**: Be aware of regional VM and API limits

## Scaling to More Nodes

For deployments with 3+ nodes:

```hcl
locals {
  vm_sequence = ["primary", "secondary1", "secondary2", "secondary3"]
}

# Create chain: primary -> secondary1 -> secondary2 -> secondary3
resource "azurerm_virtual_machine_extension" "bootstrap" {
  for_each = toset(local.vm_sequence)
  
  depends_on = [
    each.value == "primary" ? [] : [azurerm_virtual_machine_extension.bootstrap[local.vm_sequence[index(local.vm_sequence, each.value) - 1]]]
  ]
}
```

## Conclusion

The key to preventing race conditions is **explicit control over resource dependencies and execution order**. While this may make deployments slightly slower, it ensures reliability and predictability in your infrastructure provisioning.

Always test your dependency chains in a development environment before applying to production workloads.
