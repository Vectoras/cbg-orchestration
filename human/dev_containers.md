# Dev Containers — Local Development Setup Notes

> Purpose: capture what has been decided and understood about using VSCode Dev
> Containers for local development on this project, so an AI assistant (Claude
> Code) or a future contributor can pick up the reasoning without the original
> conversation. This is a working document, not a tutorial.
>
> Status legend used below:
> - **DECIDED** — settled; treat as a constraint.
> - **TO TRY** — chosen direction, not yet validated by actually running it.
> - **OPEN** — options understood, choice not yet made / needs hands-on confirmation.
> - **RULED OUT** — considered and rejected, with the reason recorded so it isn't re-litigated.

---

## 0. Context

Local dev runs four services via a single `docker compose up` in an orchestration
repo:

- `backend` — Go
- `sveltekit` — internal/staff catalogue app
- `nuxt` — customer-facing website
- `db` — PostgreSQL

Production is **out of scope for this document** — only `backend` + `db` run on the
VPS, and the frontends deploy through their own CI to external hosts. Everything
here concerns the **local development** workflow only.

Placeholders to replace with real values: `<project>` (compose project name),
`<image>` per service (e.g. `myorg-backend`).

---

## 1. Decisions (DECIDED)

### 1.1 Separate images for development and production
Dev and prod images are distinct artifacts. Every conclusion in this document
about "not baking dependencies" applies **only to the dev image**. The prod image
is a shippable artifact and follows the usual production practice (bake deps from
the committed lockfile); that is handled separately and is not discussed here.

### 1.2 Dev Node dependencies live in a named volume, not the image
For the Node services (`sveltekit`, `nuxt`) in **development**:
- The dev image bakes **nothing** — no `npm ci` in the dev Dockerfile.
- `node_modules` lives in a **named volume** mounted at the container's app dir
  (e.g. `/app/node_modules`), populated by running `npm ci` **inside the
  container**.
- The volume is reset (`docker compose down -v`) **only for clean-slate recovery**
  (corrupted volume, wedged native module), **not** on routine dependency changes.
- When a dependency changes: run `npm install <pkg>` / `npm ci` **inside the
  container** so it writes into the volume with correct Linux-native binaries.
  Never run `npm install` on the host for these services — the host path is
  shadowed by the volume inside the container, and host binaries are the wrong ABI.

**Why:** dev Node images are never deployed, so every benefit of baking (a
self-contained shippable image) is a production concern that these images don't
have. Baking into a dev image only creates the "stale volume" gotcha (see §5.2).

### 1.3 Compose-mode Dev Containers
Dev container configs point at the **existing compose files** and name a
**service**, rather than defining a standalone container. This keeps dev/prod
parity and reuses the one source of truth for the stack.

---

## 2. The workflow being adopted (TO TRY)

Goal, in the user's words: **attach multiple VSCode windows to multiple running
services at once** (work on any/all of them simultaneously), with **git-tracked,
auto-applied per-service editor config**. Owning `docker compose up`/`down`
manually is acceptable but not required.

The chosen approach is the **Reopen in Container** flow (not Attach to Running
Container — see §4 and §6.2 for why), with one config per service:

```
.devcontainer/
  backend/devcontainer.json     -> service: backend
  sveltekit/devcontainer.json   -> service: sveltekit
  nuxt/devcontainer.json         -> service: nuxt
```

Each file:
- references the **identical** `dockerComposeFile` list (same paths, same order),
- differs only in its `service` and that service's own `customizations` /
  `postCreateCommand`,
- sets **`"shutdownAction": "none"`** (critical — see §5.1).

### How to run it
1. Optionally `docker compose up -d` yourself first (see §6.2 — Reopen will attach
   to an already-running project; it does **not** require VSCode to have started
   it).
2. Open a VSCode window per service and run **"Dev Containers: Reopen in
   Container"**, selecting that service's config.
3. The **first** window brings the whole project up (if not already up); every
   **subsequent** window finds the project running and **attaches** to its
   service's live container.

Result: one shared running stack, N windows attached to N services. Because
`shutdownAction: none`, closing any window disconnects it without tearing down the
stack. `down` is manual (`docker compose down`).

### What Reopen gives back vs Attach
Each config carries its own **committed** `customizations.vscode.extensions`,
`settings`, and `postCreateCommand`. So per-service tooling (Go extension for
`backend`, Svelte extension for `sveltekit`, etc.) is version-controlled in the
repo and applied automatically. This is the shared/reproducible config that the
Attach flow could not provide.

---

## 3. Identity pinning — required for the workflow to be reliable (TO TRY / DECIDED direction)

Reopen "attaches if already running" by matching the **compose project name**.
Membership of a project = every resource carrying the label
`com.docker.compose.project=<name>`. If VSCode and your manual `up` resolve to the
**same name**, VSCode attaches to your stack; if they differ, it silently builds a
**parallel duplicate stack** (no error).

Project-name resolution precedence (highest first):
1. `-p` / `--project-name` flag
2. `COMPOSE_PROJECT_NAME` env var
3. top-level `name:` in the compose file (last file wins if several set it)
4. sanitized basename of the project directory (the fragile default —
   working-directory dependent)

**Pin it via `name:` in the base compose file** (not the directory default, not
`COMPOSE_PROJECT_NAME`). Rationale: `COMPOSE_PROJECT_NAME` usually arrives via a
`.env` loaded from the project dir, which reintroduces the working-directory
dependence we're escaping. `name:` travels inside the file and resolves the same
regardless of invocation directory.

```yaml
# docker-compose.yml (base)
name: <project>
services:
  backend:   { image: <image>-backend, ... }
  sveltekit: { image: <image>-sveltekit, ... }
  nuxt:      { image: <image>-nuxt, ... }
  db:        { image: postgres:16, ... }
```

Also pin an explicit **`image:` per service** — gives each container a stable image
identity, which matters for both this flow and (historically) for Attach-mode
config keying.

Checklist:
- [ ] `name:` set in the base compose file
- [ ] explicit `image:` on every service
- [ ] all three `devcontainer.json` files list the **same** `dockerComposeFile`
      paths in the **same order**
- [ ] `shutdownAction: none` on every config

---

## 4. Mental model (understanding, condensed)

### 4.1 Dev Containers is not a Docker feature
Three layers, three owners:
- **Docker / OCI runtime** (bottom): just runs the container; has no notion of a
  "dev container."
- **Dev Container spec — `devcontainer.json`** (middle): an **open, tool-agnostic**
  spec (containers.dev) with a reference `devcontainer` CLI that can build/run
  with no editor at all. Consumed by VSCode, the CLI, GitHub Codespaces, etc.
- **Editor integration** (top): the seamless "edit in the container" experience is
  **VSCode's own machinery** (shared by forks like Cursor; Codespaces/JetBrains
  implement their own). This is what people mean by "Dev Containers is a VSCode
  thing" — only the top layer is.

Docker never reads `devcontainer.json`. VSCode (or the CLI) reads it and drives the
Docker CLI on your behalf. You can always bypass VSCode and run `docker compose`
yourself against the identical stack.

### 4.2 Client–server split
VSCode is a UI **client** + a backend **server**. In a dev container the **server
relocates into the container** (`~/.vscode-server`, version-matched to the client
by commit hash). The UI stays on the host and just renders. Everything that
touches code — language servers, terminal, debugger, tasks, search — runs
**inside the container**, reading the container's filesystem (including the
volume-backed `node_modules`).

- Transport is **`docker exec`** stdio, not a network port. No port needs to be
  published for the editor connection.
- `extensionKind` decides placement: **UI extensions** (themes, keybindings) run on
  the host client; **workspace extensions** (language servers, linters, debuggers)
  run in the container server and must be installed there — that's what
  `customizations.vscode.extensions` does.

### 4.3 node_modules shadowing (the reason for the named volume)
A **bind mount** is a VFS mount: mounting the host project onto `/app` **occludes**
whatever the image had at `/app` (it's hidden, not deleted). So a `node_modules`
baked at build time is hidden at runtime by the bind mount → container sees the
host's (missing/wrong-ABI) deps.

Fix: mount a **named volume at `/app/node_modules`**, nested inside the bind mount.
Mounts resolve by path depth — the deeper mount wins — so:
- `/app/src`, `/app/package.json`, ... → served by the **bind mount** (live host
  edits work),
- `/app/node_modules` → served by the **volume** (container-native, isolated from
  host).

The same shadowing that caused the problem is used deliberately to solve it.

---

## 5. Gotchas to remember

### 5.1 `shutdownAction` in compose mode defaults to `stopCompose`
That default runs `docker compose stop` on the **whole project** when a window
closes — which, with multiple windows on one shared project, would yank containers
out from under the other windows. **Set `shutdownAction: none` on every config.**
Consequence: nothing brings the stack down automatically → `down` is manual.

### 5.2 The named volume is seeded only once, while empty
Docker copies an image's content into a **volume** only on **first mount while the
volume is empty**. After that the volume is never auto-refreshed. In the
volume-only dev setup nothing is baked, so `postCreateCommand: npm ci` (Reopen) or
a manual in-container `npm ci` populates it. Rebuilding the image does **not**
update an already-populated volume. Named volumes **survive `Rebuild Container`**
and plain `down`; only `down -v` removes them.

### 5.3 First-adoption restart of the attached service (see §6.1)
The first time a service is adopted into the dev-container world, its container may
be **recreated once** as VSCode's config reconciles. This is per-service,
per-stack-lifetime — **not** per window.

---

## 6. Deeper mechanics (for when it behaves unexpectedly)

### 6.1 Two separate identity checks
- **Project membership** (does Reopen attach to my stack at all?) = **project-name
  label**. Pinning `name:` guarantees this.
- **Per-container reuse** (does it reuse my exact container or recreate it?) =
  **`com.docker.compose.config-hash`** label, a hash of the service's fully
  resolved config. VSCode appends a generated override file on reopen (labels;
  possibly a keep-alive), which can change the target service's desired hash → that
  **one** container is recreated to reconcile. The other services are untouched.

**Avoiding the restart:** make the container you started already match what Reopen
wants:
- Give every attachable service a genuinely **long-running command** as its normal
  compose command (its dev server, or `sleep infinity`) so VSCode injects no
  keep-alive. `overrideCommand` already defaults to **false** in compose mode.
- Pin identity (§3) so nothing else perturbs the hash.
- Residual: VSCode may still add a tracking label your plain `up` lacked; any delta
  recreates that one container **once** on first adoption. After adoption, the
  container carries the dev-container config, so **subsequent windows onto the same
  service attach with no restart**. Routine-case restarts → zero; the very first
  adoption may not be reducible to zero depending on VSCode version, and it's
  harmless and non-recurring.

### 6.2 Reopen vs Attach — two independent axes
These got conflated and are worth separating:
- **Lifecycle ownership**: you (`docker compose up -d`) vs the first Reopen window.
- **Config source**: declared (repo `devcontainer.json`) vs bare (image-keyed,
  machine-local user settings).

"Attach to Running Container" sits at *(you own lifecycle, bare config)* — it's the
tool for attaching to a container that has **no** describing config, so it falls
back to image-keyed local settings and can't share editor config via the repo.
Reopen's default sits at *(VSCode owns lifecycle, declared config)*.

The axes are **not** welded. The combination the user wants —
*(you `up` yourself, **and** git-tracked per-service config)* — is reachable with
**Reopen**: `up -d` in your terminal first, then reopen each service (which
attaches because the project is already running), with `shutdownAction: none`.
Reopen attaching-if-already-running was never conditional on VSCode having run the
`up`; it only requires the project **name** to match.

---

## 7. Ruled out (RULED OUT)

- **Baking `node_modules` into the dev image.** Pointless for dev-only images;
  creates the stale-volume gotcha (§5.2) and would demand routine `down -v`. (Prod
  image is a separate artifact and may bake — not covered here.)
- **Attach to Running Container as the primary flow.** Gives lifecycle
  independence but pushes editor config into per-machine, image-keyed local
  settings that aren't shared through the repo. Rejected once owning `up`/`down`
  became acceptable, because Reopen returns git-tracked, auto-applied per-service
  config.
- **Relying on the default compose project name** (directory basename). Fragile,
  working-directory dependent → silent duplicate stacks. Use `name:` in the file.
- **`COMPOSE_PROJECT_NAME` via `.env`** for pinning the name. Reintroduces
  project-directory dependence; prefer `name:` inside the compose file.
- **Running `npm install` on the host** for the Node services. The path is shadowed
  by the volume inside the container, and host binaries are the wrong ABI. Installs
  must happen in the container.

---

## 8. Open questions / to validate (OPEN)

- Whether the **first-adoption restart** (§6.1) can be driven fully to zero on the
  current VSCode version, or remains a harmless one-time event. To confirm: inspect
  the `com.docker.compose.config-hash` label before/after and check whether a
  steady no-restart state is reached.
- Exact contents of each `devcontainer.json` (deferred by the user to a separate
  conversation — to be written when actually setting this up).
- `.vscode/` sharing: `settings.json`, `extensions.json` recommendations,
  `launch.json`, `tasks.json` **are** git-trackable and honored inside the
  container (they live under the bind-mounted `/app`). Confirm the desired split
  between committed `.vscode/` and per-service `devcontainer.json` `customizations`.

## 9. Deferred / not covered here
- The **dual API-URL** mechanic (SSR calling `backend` over the internal compose
  network vs the browser calling it via published ports). Flagged for a later
  conversation.
