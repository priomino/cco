# Third-party notices

This repository contains only scripts, configuration and documentation. It does not contain, and does not redistribute, any of the software below: the install scripts download it from its official source onto your machine when you run them. The terms listed are my understanding at the time of writing; the upstream projects are the authority, so please check them.

| Component | Where it comes from | Terms (as understood) |
|---|---|---|
| Claude Code | Anthropic's official installer (`https://claude.ai/install.sh`), at build time | Anthropic's terms for Claude Code. This project does not modify it. Check Anthropic's current terms and usage policies, which apply to your use. |
| Unsloth (engine and Studio) | Unsloth's official installer (`https://unsloth.ai/install.sh`), at build time | Open-source; the installer script carries an AGPL-3.0 licence header and Unsloth Studio is distributed under AGPL-3.0; other parts may use other licences. Check the Unsloth repository. |
| llama.cpp (prebuilt bundle installed by Unsloth) | Downloaded by the Unsloth installer | MIT |
| Qwen2.5-7B-Instruct (GGUF quantisation by bartowski) | Hugging Face, `bartowski/Qwen2.5-7B-Instruct-GGUF` | The Qwen2.5-7B-Instruct model is published under Apache-2.0 (verify on its model card); the quantisation inherits its terms. |
| Ubuntu 24.04 base image | Docker Hub | Various open-source licences. |
| Rancher Desktop (not included; a prerequisite) | https://rancherdesktop.io | Apache-2.0 (verify upstream). |

## Trademarks and affiliation

"Claude" and "Claude Code" are trademarks of Anthropic. "Unsloth" belongs to its owners. This project is independent and is not affiliated with, endorsed by or supported by Anthropic, Unsloth, Alibaba Cloud (Qwen) or Rancher Desktop.