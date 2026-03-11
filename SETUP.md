# ShinyProxy Auto-Deploy Setup Guide

## Overview

Auto-deploy Shiny apps to ShinyProxy on a RHEL server using GitHub Actions and GHCR (GitHub Container Registry).

**Architecture:**
- Apps are built into Docker images and pushed to GHCR on every push to `main`
- A self-hosted GitHub Actions runner on the RHEL server handles deployment locally
- ShinyProxy serves apps via nginx reverse proxy

---

## Repo Structure

```
CRI_biocore_apps/
├── .github/workflows/deploy.yml   # CI/CD workflow
├── shinyproxy/application.yml     # ShinyProxy config (source of truth)
└── apps/
    ├── 001-hello/
    │   └── Dockerfile
    ├── 006-tabsets/
    │   └── Dockerfile
    └── 050-kmeans-example/
        └── Dockerfile
```

---

## Step 1: Configure GHCR

The workflow uses the built-in `GITHUB_TOKEN` to push images to GHCR — no extra setup needed for pushing.

Image naming convention:
```
ghcr.io/<github-username>/<image-name>:latest
```

After the first successful workflow run, set images to **public** (optional):
> GitHub → your profile → Packages → each image → Package settings → Change visibility → Public

---

## Step 2: GitHub Secrets

Add these secrets in: **GitHub repo → Settings → Secrets and variables → Actions**

| Secret | Value |
|---|---|
| `GHCR_USER` | your GitHub username (e.g. `zhongyuli2026`) |
| `GHCR_TOKEN` | GitHub PAT with `read:packages` scope |
| `RHEL_HOST` | server hostname (e.g. `biocoreapps.bsd.uchicago.edu`) |
| `RHEL_USER` | SSH username on the server (e.g. `zhongyu1`) |
| `RHEL_SSH_KEY` | contents of SSH private key (see Step 3) |

> `RHEL_HOST`, `RHEL_USER`, `RHEL_SSH_KEY` are no longer used by the workflow (replaced by self-hosted runner) but kept for reference.

---

## Step 3: SSH Key Setup (for reference)

Generate a dedicated SSH key on the server:
```bash
ssh-keygen -t ed25519 -C "github-actions" -f ~/.ssh/github_actions
ssh-copy-id -i ~/.ssh/github_actions.pub zhongyu1@biocoreapps.bsd.uchicago.edu
```

Copy the private key content into the `RHEL_SSH_KEY` secret:
```bash
cat ~/.ssh/github_actions
```

---

## Step 4: Self-Hosted GitHub Actions Runner

Because the RHEL server is on a private network (firewall blocks inbound SSH from GitHub), a self-hosted runner is used instead. It connects **outbound** to GitHub on port 443 — no firewall changes needed.

### Install the runner

```bash
sudo mkdir -p /srv/actions-runner
sudo chown zhongyu1:zhongyu1 /srv/actions-runner
cd /srv/actions-runner

# Download (get exact URL from GitHub repo → Settings → Actions → Runners → New self-hosted runner)
curl -o actions-runner-linux-x64-2.332.0.tar.gz -L https://github.com/actions/runner/releases/download/v2.332.0/actions-runner-linux-x64-2.332.0.tar.gz
tar xzf ./actions-runner-linux-x64-2.332.0.tar.gz

# Configure (get token from GitHub)
./config.sh --url https://github.com/zhongyuli2026/CRI_biocore_apps --token <TOKEN>
# Press Enter for all prompts to accept defaults
```

### Install as a systemd service

```bash
chmod +x /srv/actions-runner/runsvc.sh
sudo ./svc.sh install
```

**Fix SELinux context before starting** — by default `/srv` has `var_t` SELinux context which systemd cannot execute. Relabel it to `bin_t`:

```bash
sudo chcon -R -t bin_t /srv/actions-runner/
sudo ./svc.sh start
```

The runner now starts automatically on boot and runs in the background.

### Fix passwordless sudo for the runner

```bash
sudo visudo -f /etc/sudoers.d/github-runner
```

Add:
```
zhongyu1 ALL=(ALL) NOPASSWD: /bin/cp, /bin/systemctl restart shinyproxy
```

---

## Step 5: Workflow File

`.github/workflows/deploy.yml`:

```yaml
name: Build & Deploy Shiny Apps

on:
  push:
    branches: [main]

jobs:
  build-and-push:
    permissions:
      packages: write
    runs-on: ubuntu-latest
    strategy:
      matrix:
        app:
          - name: 001-hello
            image: shiny-001-hello
          - name: 006-tabsets
            image: shiny-006-tabsets
          - name: 050-kmeans-example
            image: shiny-050-kmeans-example
    steps:
      - uses: actions/checkout@v4
      - uses: docker/login-action@v3
        with:
          registry: ghcr.io
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}
      - uses: docker/setup-buildx-action@v3
      - uses: docker/build-push-action@v5
        with:
          context: apps/${{ matrix.app.name }}
          push: true
          tags: ghcr.io/${{ github.repository_owner }}/${{ matrix.app.image }}:latest

  deploy:
    needs: build-and-push
    runs-on: self-hosted
    steps:
      - uses: actions/checkout@v4
      - name: Deploy
        run: |
          sudo cp shinyproxy/application.yml /etc/shinyproxy/application.yml
          echo ${{ secrets.GHCR_TOKEN }} | docker login ghcr.io -u ${{ secrets.GHCR_USER }} --password-stdin
          docker pull ghcr.io/${{ secrets.GHCR_USER }}/shiny-001-hello:latest
          docker pull ghcr.io/${{ secrets.GHCR_USER }}/shiny-006-tabsets:latest
          docker pull ghcr.io/${{ secrets.GHCR_USER }}/shiny-050-kmeans-example:latest
          sudo systemctl restart shinyproxy
          docker image prune -f
```

---

## Step 6: ShinyProxy Config

`shinyproxy/application.yml` is the **single source of truth** — it is copied to `/etc/shinyproxy/application.yml` on every deploy. Do not edit the file directly on the server.

```yaml
server:
  servlet:
    context-path: /apps

proxy:
  title: "My Shiny Apps"
  port: 8080
  authentication: simple
  users:
    - name: admin
      password: changeme
  docker:
    internal-networking: false
    url: http://localhost:2375
  specs:
    - id: hello
      display-name: "Hello Shiny"
      container-image: ghcr.io/zhongyuli2026/shiny-001-hello:latest
      port: 3838
    - id: tabsets
      display-name: "Tabsets"
      container-image: ghcr.io/zhongyuli2026/shiny-006-tabsets:latest
      port: 3838
    - id: kmeans
      display-name: "K-Means Clustering"
      container-image: ghcr.io/zhongyuli2026/shiny-050-kmeans-example:latest
      port: 3838
```

---

## Nginx Config

ShinyProxy is accessible at `/apps/` via nginx reverse proxy:

```nginx
location /apps/ {
    proxy_pass http://localhost:8080/apps/;
    proxy_redirect http://localhost:8080/apps/ $scheme://$host/apps/;
    proxy_buffering off;
    proxy_request_buffering off;
}
```

ShinyProxy login page: `https://biocoreapps.bsd.uchicago.edu/apps/login`

---

## Adding a New App

1. Create `apps/<app-name>/Dockerfile` in the repo
2. Add the app to the matrix in `deploy.yml`
3. Add a `docker pull` line for the new image in the deploy job in `deploy.yml`
4. Add the app spec to `shinyproxy/application.yml`
5. Push to `main` — the workflow builds, pushes, and deploys automatically

---

## Docker Build Caching

Every push rebuilds all apps in the matrix. To avoid slow full rebuilds for unchanged apps, the workflow uses **registry-based Docker layer caching**:

```yaml
cache-from: type=registry,ref=ghcr.io/<owner>/<image>:cache
cache-to: type=registry,ref=ghcr.io/<owner>/<image>:cache,mode=max
```

If a `Dockerfile` and app files haven't changed since the last build, Docker reuses cached layers and the build completes in seconds. Only apps with actual changes do a full rebuild.

---

## Key Notes

- `internal-networking: false` is required because ShinyProxy runs as a Java process (not in Docker) and cannot join Docker networks
- `context-path: /apps` aligns ShinyProxy's URL structure with the nginx `/apps/` location block
- The self-hosted runner is used because the university perimeter firewall blocks inbound port 22 from GitHub Actions IPs
- SELinux on RHEL blocks execution of scripts in `/srv` by default — fix with `sudo chcon -R -t bin_t /srv/actions-runner/` before starting the runner service
- `shinyproxy/application.yml` in the repo is the single source of truth — never edit it directly on the server as it will be overwritten on the next deploy
