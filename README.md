# NexCore v0.3.3

**The modular, modern, and secure microkernel for NeetComputers**

---

## Overview

NexCore is a capability-based microkernel plus a single, authoritative system registry that together provide a flexible foundation for building general-purpose operating systems on the NeetComputers platform.

NexCore intentionally implements a minimal kernel: as much policy and functionality as possible runs in user space. The registry is the single source of truth for system configuration, driver and module locations, user records, defaults, and backups. That separation enables extreme flexibility. You define the OS by editing the registry, not by changing the kernel.

NexCore is a kernel + registry. It does not try to be a full OS distribution. It provides the primitives and a small, consistent surface that others can use to implement shells, init systems, package managers, or full desktop/server environments.

---

## Key Principles

* **Modularity**: Everything outside the kernel is replaceable. Filesystem layout, init, package manager, and UI are choices you make.
* **Capability-based security**: IPC and resource access are capability-oriented, keeping the kernel minimal and safe.
* **Single source of truth**: The registry (`/core/registry/system.reg`) encodes the configuration the kernel relies on.
* **Human-readable configuration**: The registry uses JSON to make inspection, diffing, and editing straightforward.

---

## Architecture (high level)

* **Microkernel**: capability-based, message-passing oriented. The kernel implements only the smallest possible primitives: capability checks, IPC, scheduling, and boot initialization.
* **Registry**: a set of files under `/core/registry/`. The kernel reads `system.reg` at boot and may re-read it at runtime when requested. The registry controls driver locations, module locations, init paths, and user records.
* **Userland**: drivers, device managers, filesystems, and higher-level services live in user space and interact with the kernel through capabilities and IPC.

---

## The Registry

The registry is the single source of truth for NexCore. It is intentionally simple and composed of a few well-known files under the hard-coded path `/core/registry/`:

* `system.reg` the kernel-visible root registry file (JSON).
* `user_[username].reg` per-user configuration and preferences (JSON).
* `defaults.reg` system defaults (JSON).
* `backups/` optional directory for registry snapshots.

**Notes:**

* The registry format is JSON for readability and ease of tooling. Multiple parsers and editors can be built around it.
* The registry files are considered authoritative and are therefore a single hard requirement for NexCore; the kernel expects them under `/core/registry/`.
* Password hashes are stored in the registry but may only be modified by the root user. The system is designed with security in mind, but service authors should follow best practices for hashing and key management.

---

## Runtime behavior

* `system.reg` is read at boot. The kernel may support reloading parts of the registry at runtime, but not all changes are guaranteed to take effect without a restart. Treat runtime updates as potentially requiring a reboot for full effect.
* Editing the registry is manual in the current design (this repository contains kernel + registry primitives only). Higher-level tools and editors are planned to provide safer editing in the future.

---

## Drivers & Modules

Drivers and kernel modules are provided by userland components and located where `system.reg` points. The registry exposes `driver_locations` and `module_locations` so distributions built on NexCore can organize drivers however they prefer.

The driver API (loader, capability registration, lifecycle) is a work in progress and will be published in the API documentation as the project progresses.

---

## Status & Roadmap

**Near-term roadmap:**

* Define the driver/module loading API and publish the first specification.
* Document the capability-based IPC model and security primitives.
* Prototype the advanced security model and the DQRR scheduler.
* Add `npr`, a registry-aware package format/manager design.

**Long-term goals:**

* A stable kernel ABI for drivers and services.
* Tooling for safe registry edits and runtime reconfiguration.
* Reference userland components (init, shell, minimal userspace) to help adopters bootstrap.

---

## Compatibility & Platform

NexCore targets the NeetComputers platform.

---

## Security

Security is a fundamental design goal:

* Password hashes stored in the registry are only writable by root or by tools with explicit capabilities.
* Future work will define secure update paths for the registry, signed backups, and protected edits.

---

## APIs

APIs and bindings are currently under design. Planned surface areas include:

* Driver loading and capability registration.
* Registry read/write helpers and validation schemas.
* IPC primitives for capability-based communication.

---

**Contact:**

* GitHub: `https://github.com/RedSoftware-US/NexCore`
* Discord: `red.software`
* Email: `redsoftware-us@proton.me`

---

## License

NexCore is released under the Apache License 2.0.

---

## FAQ (brief)

**Q: Is NexCore an OS?**
A: No. NexCore is a kernel + registry. It provides the primitive surface on which complete operating systems can be built.

**Q: Can I change the registry location?**
A: Not currently. The registry path `/core/registry/` is a hard requirement for the kernel design.

**Q: Can changes be made at runtime?**
A: Parts of the registry can be reloaded at runtime but not all changes are guaranteed to take effect until a reboot.
