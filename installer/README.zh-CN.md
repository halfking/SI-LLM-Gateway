# llm-gateway-go One-Click Installer

> Cross-platform Go installer for Windows / Linux / macOS / Domestic OS / Domestic CPU.
> Built-in 4-tier image source fallback: offline package → internal registry → domestic mirror → official hub.

[简体中文](README.zh-CN.md)

---

## Directory Structure

```
installer/
├── cmd/llm-gw-installer/
│   ├── main.go              # Cobra CLI entry
│   └── embeddata/           # go:embed resources (compose.yml / SQL / templates)
├── internal/
│   ├── envdetect/           # OS/arch/docker/network detection
│   ├── imgsrc/              # 4-tier image source fallback
│   ├── prompt/              # 11-step interactive wizard
│   ├── secrets/             # Random password + .env generation
│   ├── dockerutil/          # Compose wrapper + health check
│   ├── dbinit/              # SQL schema application
│   └── report/              # Deployment report generation
├── templates/               # Template source files (synced to embeddata/)
├── sql/                     # Reuse from deploy/sql/
├── go.mod
└── README.md
```

## Quick Start

```bash
# Build for current platform
GOPROXY=https://goproxy.cn,direct go build -o /tmp/llm-gw-installer ./cmd/llm-gw-installer/

# Test
/tmp/llm-gw-installer doctor
/tmp/llm-gw-installer install

# Cross-compile
make cross-compile   # See Makefile below (optional)
```

## Commands

```
llm-gw-installer doctor      # Environment check (OS/docker/network/ports)
llm-gw-installer install     # One-click install and deploy
llm-gw-installer uninstall   # Uninstall (--purge for complete cleanup)
```

## Cross-Platform Build

```bash
# Linux/macOS
GOOS=linux  GOARCH=amd64 go build -o dist/llm-gw-installer-linux-amd64 ./cmd/llm-gw-installer/
GOOS=linux  GOARCH=arm64 go build -o dist/llm-gw-installer-linux-arm64 ./cmd/llm-gw-installer/
GOOS=linux  GOARCH=loong64 go build -o dist/llm-gw-installer-linux-loong64 ./cmd/llm-gw-installer/
GOOS=darwin GOARCH=amd64 go build -o dist/llm-gw-installer-darwin-amd64 ./cmd/llm-gw-installer/
GOOS=darwin GOARCH=arm64 go build -o dist/llm-gw-installer-darwin-arm64 ./cmd/llm-gw-installer/
GOOS=windows GOARCH=amd64 go build -o dist/llm-gw-installer-windows-amd64.exe ./cmd/llm-gw-installer/
GOOS=windows GOARCH=arm64 go build -o dist/llm-gw-installer-windows-arm64.exe ./cmd/llm-gw-installer/
```

## Environment Variables

| Variable | Default | Purpose |
|---|---|---|
| `KX_REGISTRY` | `registry.kxpms.cn` | Custom internal registry |
| `KX_REGISTRY_USERNAME` | empty | Custom registry username |
| `KX_REGISTRY_PASSWORD` | empty | Custom registry password |
| `KX_REGISTRY_INSECURE` | `false` | Allow HTTP |
| `APP_IMAGE_TAG` | From MANIFEST | Override app image tag |
| `GOPROXY` | `https://goproxy.cn,direct` | Go module proxy |

## Image Source Fallback Chain

```
[1] Offline package images/*.tar.gz (highest priority)
    ↓ failed
[2] registry.kxpms.cn (internal registry)
    ↓ failed
[3] registry.cn-hangzhou.aliyuncs.com (Aliyun mirror)
    ↓ failed
[4] registry-1.docker.io (official Docker Hub)
    ↓ all failed
❌ Clear error message
```

## Unit Tests

```bash
go test ./...
```

## Embedded Resources

All SQL files, compose templates, and report templates are embedded via `go:embed`:

```go
//go:embed embeddata/compose.yml
var composeYAML []byte

//go:embed embeddata/00-prereqs.sql
var sqlPrereqs []byte
// ...
```

After modifying templates, sync to `cmd/llm-gw-installer/embeddata/`.

## Integration Tests

End-to-end tests require real Docker environment. Recommended in CI:

```bash
make test-e2e
```

Test scenarios:
1. Scenario A: Complete offline package → direct load success
2. Scenario B: Corrupted offline package + internal network → pull from registry.kxpms.cn
3. Scenario C: Internal network down + public network up → pull from Aliyun mirror
4. Scenario D: Completely offline → clear error
5. Domestic OS: Auto-install Docker + full workflow

## Known Limitations

- **HarmonyOS NEXT**: Not supported (no Linux container support)
- **macOS**: Users must manually install OrbStack or Docker Desktop
- **Windows**: Users must manually install Docker Desktop + WSL2

---

## Language Note

The installer CLI prompts are currently in Chinese. The core functionality works on all platforms. For English-speaking users, the installation flow is straightforward:

1. Run `./llm-gw-installer doctor` to check prerequisites
2. Run `./llm-gw-installer install` and follow the prompts
3. Default values are shown in brackets - press Enter to accept

Full i18n support is planned for future releases.
