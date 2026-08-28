# Project Decisions

Reference documentation for the charity book cataloguing product. It records
what has been decided, what is deliberately ruled out, and what remains open.

**If you are an AI assistant or a contributor working on this project:** treat
the *Decisions* and *Ruled out* sections as settled. Do not propose alternatives
to them unless a decision is explicitly reopened, or unless you have identified a
concrete blocking problem — in which case say so directly rather than quietly
substituting a different approach. The *Open questions* and *Unresolved problems*
sections are where input is genuinely wanted.

---

## 1. Overview

A multi-app product for a small charity, backed by a single source of truth. A Go
backend and a self-hosted PostgreSQL database hold the book inventory; two
separate frontend applications consume it.

The project serves two purposes at once: it is a real production deployment for
the charity, and it is a portfolio piece (a first substantial Go project). Both
purposes legitimately influence decisions.

### Components

| Component | Status | Purpose |
| --- | --- | --- |
| Go backend | To be built | API, ISBN validation, external lookup, persistence |
| PostgreSQL | To be deployed | Single source of truth for inventory |
| Customer-facing website (Nuxt) | Advanced, in progress | Public site; to be enhanced with catalogue/inventory lookup |
| Internal / staff app | To be built | Inventory management tool; barcode/image scanning is a major feature |

Each component lives in its own repository, wired together by an orchestration
repository.

### What the product does

Books are catalogued individually (not by shelf or in bulk). A staff member
scans a book's barcode in the internal app; the ISBN is decoded client-side and
sent to the backend, which validates it, looks up the book's details from
external APIs, and persists the record. The catalogue is then queryable from the
public website.

---

## 2. Constraints and guiding principles

- **Cost sensitivity applies to the whole stack**, not just AI usage. Free and
  low-cost tiers are preferred throughout, and pricing is a first-class filter on
  every infrastructure choice.
- **AI usage is deliberately minimal** and reserved for a single rare edge case.
  Do not introduce AI into paths that can be handled deterministically.
- **Latency is not a concern.** Do not trade cost or simplicity for speed.
- **The production server has 1 GB of RAM.** This is a hard ceiling and the
  binding constraint on most runtime decisions. Every service running on it needs
  an enforced memory limit, and actual usage needs monitoring.
- **UK/EU data residency is a strong preference, not a hard requirement.** It is
  the default tie-breaker given the charity's governance context, but a
  significant enough cost saving can outweigh it.
- **The project is a learning exercise as much as a delivery.** Understanding the
  mechanics of a solution matters; opaque solutions that work but are not
  understood are not preferred.

---

## 3. Decisions

### 3.1 Backend

- **Language: Go.**
- **Backend contract:** in the normal case the client sends a plain ISBN string.
  The backend re-validates the checksum server-side, performs the lookup, and
  persists the result. This path is fully deterministic — no AI involved.
- **Images are only ever sent to the backend in the single AI edge case**
  described in 3.5. Normal scanning does not upload images.

### 3.2 Database

- **PostgreSQL, accessed from Go via the `pgx` driver.**
- **Self-hosted** in both local development and production, running in Docker.
- Data persists via a named Docker volume.
- Schema and seed SQL are **versioned in the repository** and applied from there,
  not applied ad hoc against a running database.

### 3.3 Frontends

Two separate applications, in separate repositories, for different audiences.

**Customer-facing website — Nuxt.**
- Already in an advanced state of development.
- **Statically generated (SSG).** The site is simple, and the only dynamic
  element it will ever have is the catalogue/inventory lookup.

**Internal / staff app — to be built.**
- An internal tool for inventory management. Barcode and image scanning is a
  major feature, but the app is not limited to scanning and may gain unrelated
  features.
- Built as a **PWA**, chosen specifically because image scanning is central to it
  (camera access, installability, offline-tolerant behaviour).
- Framework not yet chosen — see Open questions (4.1).

### 3.4 Barcode scanning

- Scanning happens **client-side, in the internal app**, using a JS/TS npm
  library. It is not done on the backend, and not done against raw browser APIs
  directly.
- The approach is a **maintained ZBar-WASM-based decoder**, wrapped in a small
  component.
- No OCR is involved in barcode decoding.
- The specific package is not yet chosen — see Open questions (4.3).

### 3.5 Book lookup and AI usage

- **Two data sources: Google Books and Open Library.** Both are used.
- **Primary path — by ISBN.** An exact lookup. This covers the overwhelming
  majority of cases.
- **Secondary path — by details.** A search on title, author, year and similar
  fields, returning ranked candidates. This requires matching logic to pick or
  rank results.
- **AI path — cover-only identification.** A vision LLM is used for one rare
  case only: a book with no readable ISBN anywhere, which must be identified from
  the title and author printed on its cover. The model returns structured output
  mapped to a typed Go struct. This is the only path that sends images to the
  backend.

### 3.6 MCP

- MCP is **not a goal and not required** for this project.
- It may optionally be added later. If it is, it wraps **the book-lookup step
  only**.
- **Database writes deliberately do not go through MCP.**

### 3.7 Hosting and infrastructure

- **Backend and database host:** a Cloudzy VPS — 1 GB RAM, London region, billed
  annually.
- **Operating system:** Ubuntu 24.04 LTS.
- **Containerisation: Docker**, in both local development and production.
- **Production runs only the backend and the database on the VPS.** Both
  frontends are built and deployed separately through their own CI pipelines to
  external hosts, so the VPS needs no Node or frontend build toolchain. Production
  images are pulled pre-built from a registry.
- Per-service memory limits are mandatory in production given the 1 GB ceiling.
- Frontend hosting provider is not yet chosen — see Open questions (4.2).

### 3.8 Email

- **Provider: Mailjet.** Chosen for a 6,000 emails/month free tier (subject to a
  200/day sub-cap), EU-based infrastructure, and a straightforward REST API.
- **Integration: plain `net/http` from Go.** No SDK dependency.
- Authentication uses a **public/private API key pair** (not a single bearer
  token).
- **All email goes over HTTPS on port 443 via the REST API.** There is no SMTP
  client and no dependency on ports 25, 465 or 587. VPS providers block outbound
  port 25 almost universally; this stack is unaffected by that, and SMTP port
  availability is not a factor in any hosting decision.
- Domain verification (SPF/DKIM) is an outstanding setup task.

### 3.9 Observability

- **A lightweight local metrics agent on the VPS ships metrics to Grafana Cloud's
  free tier** (approximately 10,000 active series, 14-day retention).
- Dashboards and storage are managed by Grafana Cloud rather than self-hosted.

---

## 4. Open questions

### 4.1 Internal app framework
Svelte is the preferred option; Vue is the fallback. The decision depends partly
on the UI component libraries available for each. This choice applies only to the
internal app — the customer website is already built in Nuxt.

### 4.2 Frontend hosting provider
Netlify is the current lean. Cloudflare Pages is also under consideration, partly
for its portfolio value. Neither is committed.

### 4.3 Barcode scanning package
Two directions under consideration: a direct ZBar-WASM library (for example
`web-wasm-barcode-reader`), or a `BarcodeDetector` polyfill approach that backs
the standard browser API with WASM so the standard API can be coded against.

### 4.4 Docker Compose file strategy
Docker itself is settled (3.7); what is open is how the Compose files are
organised across the orchestration repository and the app repositories. One
candidate approach is a three-file layout:
- a shared base file defining service shapes without build or image references;
- a dev overlay, auto-loaded by Docker Compose, adding `build:` contexts and
  hot-reload volumes;
- a prod overlay, applied explicitly on the VPS, using pre-built registry images
  and per-service memory limits.

Related sub-questions: whether local development brings up all services with a
single command; and how the orchestration repository references the app
repositories for build contexts (for example, sibling-directory cloning with
relative paths, kept out of version control).

Useful mechanics to bear in mind when deciding: Compose merges files left to
right; scalar values are overridden, maps are merged key by key, and **lists are
appended rather than replaced** unless the `!override` tag is used.
`docker compose config` prints the fully merged result without starting
anything, which is the way to verify a layered setup does what is intended.

### 4.5 Reconciling the two lookup sources
When both Google Books and Open Library return data for the same ISBN, it is not
decided whether to merge the results field by field or to treat one source as
primary and the other as a fallback.

### 4.6 Candidate confirmation in the by-details path
Whether the by-details search surfaces its ranked candidates to the user for
confirmation before saving. Doing so is recommended, since the match is
inherently uncertain, but it is not committed.

---

## 5. Unresolved problems

These are known difficulties without a satisfactory answer yet — distinct from
open questions, where the options are understood and simply not chosen.

### 5.1 `node_modules` visibility between container and IDE
When a frontend's source directory is bind-mounted from the host into a
container, the host's `node_modules` shadows the one installed inside the
container, which breaks native dependencies built for the container's platform.
The conventional fix is an anonymous volume mounted at the container's
`node_modules` path, which masks the host directory.

That fix creates a second problem: with dependencies installed only inside the
container, VS Code on the host cannot see them, so TypeScript checking, linting,
and editor tooling stop working. A solution is needed that keeps both the
container runtime and the host IDE working. Options not yet evaluated include
dev containers, installing dependencies on both sides, or avoiding the bind-mount
pattern altogether.

### 5.2 Dual API URL pattern — not yet understood
There is a known pattern where a frontend needs two different URLs for the same
backend: an internal container-network address for requests made during
server-side rendering, and a public/published address for requests made from the
browser. **This pattern has not yet been understood well enough to adopt or
dismiss, and needs explaining before it is applied.**

It may turn out not to apply here at all: the problem arises specifically when a
framework renders pages on a server. If the customer website is fully static and
the internal app renders in the browser, there may be no server-side rendering
step and therefore only ever one API URL.

---

## 6. Ruled out

Recorded so these are not revisited without reason.

| Option | Why it was ruled out |
| --- | --- |
| Managed PostgreSQL (e.g. Neon) | Self-hosting on the existing VPS is cheaper and keeps data under direct control |
| Native mobile apps | A PWA covers the scanning requirement without app store overhead |
| `zxing-js`, `html5-qrcode` | Effectively unmaintained |
| Raw browser barcode APIs, or backend-side scanning | Scanning belongs client-side via a maintained library |
| Self-hosted Prometheus + Grafana | Too RAM-heavy for a 1 GB server |
| SMTP relay for email | The REST API over HTTPS is simpler and avoids all port-blocking concerns |
| An email provider SDK | Plain `net/http` is sufficient for the small number of calls involved |
| Render free tier | Cold starts unacceptable for a public-facing service |
| Hetzner | Best value, but no UK data centre |
| IONOS VPS | Post-introductory pricing too high |
| CentOS | Effectively end-of-life |
| Alpine Linux | musl and OpenRC friction not worth the RAM saving, which addressed OS overhead rather than PostgreSQL's own memory needs |
| Non-Docker deployment (native binary + systemd, Podman, LXC/LXD, Nix) | Considered; Docker chosen for both local and production for dev/prod parity |
| MCP for database writes | Deliberately excluded; MCP is scoped to book lookup only, if used at all |

---

## 7. Outstanding setup tasks

- Complete Mailjet domain verification (SPF/DKIM) and implement the Go
  integration.
- Provision and configure the Cloudzy VPS.
