---
name: sandbox-manager
description: Create and manage isolated application sandboxes (Next.js, Python, PHP, etc.) with public URLs via Cloudflare.
metadata:
  openclaw:
    emoji: 📦
    requires:
      bins: ["docker", "sqlite3", "curl"]
      env: []
    install:
      - id: "cloudflared"
        kind: "download"
        url: "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64"
        bins: ["cloudflared"]
---

# Sandbox Manager

This skill allows you to spin up isolated "sandboxes" for various application stacks. Each sandbox is a Docker container with:
- A persistent volume.
- A specific technology stack (Node/Bun, Python/UV, PHP/Composer, etc.).
- A publicly accessible URL via Cloudflare Tunnel.
- An entry in the local `sandboxes.db` registry.

## Actions

### Create a Sandbox
Create a new project container.
```bash
{baseDir}/scripts/create_sandbox.sh --stack <stack> --title <title>
```
Supported stacks: `nextjs`, `fastapi`, `laravel`, `rails`, `gin`, `springboot`, `dotnet`, `axum`, `ktor`, `vapor`, `flutter`, `phoenix`.

### List Sandboxes
View all active sandboxes and their URLs.
```bash
{baseDir}/scripts/list_sandboxes.sh
```

### Delete a Sandbox
Remove a container and its database entry (optionally keep volume).
```bash
{baseDir}/scripts/delete_sandbox.sh --name <container_name>
```
