# llm-gateway-go One-Click Installer

[English](#english) | [简体中文](README.zh-CN.md)

---

<a name="english"></a>
## English

### Overview

Cross-platform Go installer for Windows / Linux / macOS / Domestic OS / Domestic CPU.

**Features**:
- One-click deployment with interactive wizard
- 4-tier image source fallback (offline → internal registry → mirror → official hub)
- Automatic Docker installation for supported Linux distributions
- Multi-architecture support (amd64, arm64, loong64)

### Quick Start

```bash
# Build
go build -o llm-gw-installer ./cmd/llm-gw-installer/

# Check prerequisites
./llm-gw-installer doctor

# Install
./llm-gw-installer install
```

### Commands

```
llm-gw-installer doctor      # Environment check
llm-gw-installer install     # One-click install
llm-gw-installer uninstall   # Uninstall
```

### Known Limitations

- **CLI prompts are currently in Chinese**. Default values are shown in brackets - press Enter to accept.
- **macOS**: Requires manual Docker Desktop or OrbStack installation
- **Windows**: Requires manual Docker Desktop + WSL2 installation
- **HarmonyOS NEXT**: Not supported

Full documentation: [README.zh-CN.md](README.zh-CN.md)

---

<a name="中文"></a>
## 简体中文

完整文档请查看 [README.zh-CN.md](README.zh-CN.md)
