# ChromeOS ARCVM SukiSU Ultra Kernel AI Assistant Guide

## 🎯 Project Overview
This repository contains a custom ChromeOS ARCVM kernel with integrated SukiSU Ultra (KernelSU) and SUSFS support. The project enables root access on ChromeOS devices while providing root detection bypass capabilities.

## 🏗️ Architecture

### Core Components
1. **ChromeOS ARCVM Kernel**
   - Base: ChromeOS kernel from chromium.googlesource.com
   - Architecture: x86_64 focused
   - Key file: `/opt/google/containers/android/system.raw.img` (target installation path)

2. **SukiSU Ultra Integration**
   - KernelSU-based root management
   - Version tracking via `KSU_VERSION` in build pipeline
   - Configured via kernel config flags (CONFIG_KSU, CONFIG_KPM)

3. **SUSFS Framework**
   - Root detection bypass system
   - VFS hooks and mount management
   - Location: `susfs4ksu/` directory during build

### Build System Integration
- GitHub Actions workflow in `.github/workflows/build-kernel.yml`
- Configurable builds via workflow dispatch inputs
- Automated artifact generation and packaging

## 🛠️ Development Workflows

### Building the Kernel
Key entry points:
```bash
# Local development
./BUILD_INSTRUCTIONS.sh  # Main build script
make ARCH=x86_64 chromiumos-x86_64_defconfig  # Configure kernel
make ARCH=x86_64 -j$(nproc) bzImage modules   # Build kernel
```

### Essential File Paths
- `ChromeOS_ARCVM_SukiSU_Ultra_x86_64_Kernel.yml` - Main workflow definition
- `setup_repo.sh` - Repository initialization script
- `.github/workflows/build-kernel.yml` - Build pipeline definition

## 🔑 Critical Patterns

### Configuration Management
1. Kernel Configuration:
   - VFS Hooks: CONFIG_KSU_MANUAL_HOOK
   - SUSFS Settings: CONFIG_KSU_SUSFS_*
   - Base Config: chromiumos-x86_64_defconfig/chromeos_defconfig

2. Build Options:
   ```yaml
   - KERNEL_BRANCH: [chromeos-5.10-arcvm, chromeos-5.15-arcvm, ...]
   - ANDROID_VERSION: [android12, android13, android14, android15]
   - KERNEL_VERSION: ["5.10", "5.15", "6.1", "6.6"]
   ```

### Patch Management
1. SUSFS Patches:
   - Naming: `50_add_susfs_in_gki-${ANDROID_VERSION}-${KERNEL_VERSION}.patch`
   - Application order: SUSFS → Hide Stuff → VFS Hooks → LZ4KD

2. Feature Toggles:
   - VFS Manual Hooks
   - KPM (Kernel Patch Module)
   - ZRAM Enhancement

## 🚨 Common Pitfalls

1. Build Environment:
   - Required deps: python3, git, curl, bc, bison, flex, libssl-dev, libelf-dev
   - ccache configuration critical for build performance

2. Path Handling:
   - Always use absolute paths for kernel image operations
   - Critical path: `/opt/google/containers/android/system.raw.img`

3. Configuration:
   - Don't mix VFS hooks with standard KPROBES config
   - ZRAM features require specific kernel version support

## 📝 Response Templates

### Build Error Response:
```
Build failure detected. Please check:
1. Build dependencies (run setup_repo.sh)
2. Kernel configuration compatibility
3. Patch application status
4. Build logs in workflow artifacts
```

### Installation Guide Response:
```
Please follow these steps:
1. Enable ChromeOS Developer Mode
2. Extract kernel package
3. Run install_chromeos.sh
4. Install KernelSU Manager
5. Flash SUSFS module
```

## 🔄 Workflow Integration

When handling user requests:
1. Check Android version compatibility first
2. Verify kernel branch support
3. Consider feature toggle implications
4. Reference build artifacts for examples
5. Use existing scripts over manual commands

## 🏷️ Version Conventions
- Kernel versions: Follow ChromeOS ARCVM branches
- SukiSU Version: Build number + 10606 offset
- Package naming: CHROMEBOOK-ARCVM-x86_64-SUKISU-ULTRA-SUSFS-KERNEL_[FEATURES]