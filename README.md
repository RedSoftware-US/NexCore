# NexCore
The modular, modern, and secure kernel for NeetComputers.

## Overview
NexCore is a kernel + registry designed to let you define your operating system.

It does not impose a filesystem layout, init system, or package manager. It does not assume your workflow, your UI, or your tools. The registry is the single source of truth, and everything else is modular and replaceable.

There is no "correct" way to build on Nex. Only your way.

The reason Nex is able to be so modular is the kernel + registry architecture. It is a microkernel design which already allows flexibility, and the registry puts this to the max. While the Windows, Mac, and Linux kernels will force a specific filesystem layout or driver location, Nex does not care. You can build a Windows clone on Nex, a Linux clone, or whatever you desire. Everything in the Nex kernel that can reasonably be seen as an option you might want to change is available to change inside of the registry.

## Key Concepts

### What is the system registry?
The system registry is the single source of truth for the Nex kernel. The system registry must live inside of `/core/registry/`. Inside of `registry/`, the kernel only cares about `system.reg`. Inside of `system.reg`, key filesystem locations such as drivers, kernel modules, and more are defined. Everything the kernel needs to know which is reasonably seen as changeable is available for modification there.

### How does the registry define system configuration?
Inside of `system.reg`, which is internally a JSON file, parameters such as `SYSTEM.KERNEL.driver_locations` and `SYSTEM.KERNEL.module_locations` can be defined. `system.reg` also contains the user password hashes, under `SYSTEM.USERS.[username].password_hash`.

Inside of `user_[username].reg`, specific user configs for things such as applications are available. Shell configuration would be under `SHELL.location`, `SHELL.PATH`, `SHELL.aliases`, and other entries OS specific.

### Benefits of this design
Nex's kernel + registry architecture allows for systems to be completely customizable, and allows people to build operating systems ontop of the kernel to fit their exact needs without conforming to any specific design idea, aside from the kernel + registry. On a Windows-like clone, you have the potential to run basic apps which were written for a Linux-like clone, as they can share the same common kernel! This design ensures that even when developers have wildly different goals, a common interface can be achieved, and the wheel does not need to be reinvented each time.

## Usage
The Nex kernel can be copied with a provided template, and by simply providing your own `SYSTEM.KERNEL.init` file path, you can get started with building your OS.

### APIs
**APIs are not yet defined**

## Future work & known issues
Nex is still in very heavy development. More to come soon.

## License and contact info
Nex is licensed under the Apache License 2.0. \
\
\
Discord: swoshswosh_01578

Email: swoshswosh@proton.me

Github: SpartanSf

https://github.com/SpartanSf/NexCore
