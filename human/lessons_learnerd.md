# 1. Extension signature verification fails on `-slim` base images

**Symptom:** installing a VS Code extension inside a container-based dev
environment gets stuck — the extension stays disabled with *"This extension
is disabled in this workspace because it is defined to run in the Remote
Extension Host..."*, and a notification reads *"Signature verification
failed with 'UnknownError'"*. Clicking "Install in Dev Container" repeatedly
does not resolve it.

**Root cause:** Debian's `-slim` image variants strip out the
`ca-certificates` package to save space, so there is no CA trust store at all
(`/etc/ssl/certs` is empty). VS Code Server's extension signature check
(`@vscode/vsce-sign`) needs that trust store to validate a certificate chain;
without it, the check fails with an opaque `UnknownError` rather than a
message pointing at the actual cause.

Confirmed empirically: a full (non-slim) Debian-based image doesn't hit this,
but only because it happens to include `ca-certificates` already — not
because anyone decided it was needed for this purpose. Switching to the full
image would have hidden the real dependency rather than fixed it, so keeping
the slim image plus an explicit, documented install is the better fix.

**Fix:** install `ca-certificates` explicitly in the Dockerfile:

```dockerfile
# Debian slim strips ca-certificates to save space; without it there's no CA
# trust store at all (/etc/ssl/certs is empty), which breaks anything that
# validates a certificate chain — notably VS Code Server's extension
# signature verification (surfaces as a vague "Signature verification failed
# with 'UnknownError'" notification, with no indication it's a missing
# trust store).
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates \
	&& rm -rf /var/lib/apt/lists/*
```

**General principle:** when a minimal base image starts failing in a way
that looks unrelated to anything you installed, suspect a stripped-out OS
package before suspecting your own config — especially anything doing TLS,
locale, or timezone handling, which minimal images commonly omit.

# 2. Alpine's musl libc can break native npm dependencies

**Problem:** Alpine uses **musl** libc instead of **glibc**. Native npm
dependencies (packages with compiled C/C++ addons, built via `node-gyp`)
often ship prebuilt binaries targeting glibc, or need a full build toolchain
to compile from source on musl. This friction doesn't show up until a
project happens to add the wrong dependency, at which point it can mean a
failing `npm install`, a missing build toolchain, or a package that installs
fine but misbehaves at runtime in musl-specific ways.

**Mitigation:** use a glibc-based image (e.g. Debian's `-slim` variants)
instead of Alpine for a Node environment, particularly when the usual reason
to pick Alpine — its smaller image size — doesn't actually pay off for the
use case. For a local dev container, disk size is often irrelevant, and
Alpine's `malloc` behaviour can in some cases make a Node process use *more*
memory than glibc's, undercutting the size argument anyway. Weigh the
concrete risk to native dependencies against whatever benefit Alpine is
actually being chosen for, rather than defaulting to it.

# 3. Dev/prod base-image parity matters only where the same image ships to prod

**Question raised:** should dev containers standardise on larger, fuller
base images generally (fewer surprises, less whack-a-mole), even when
production images stay minimal?

**Answer: it depends entirely on whether production ever runs the same
image.**

- **When production doesn't run the dev-built image at all** — e.g. a
  frontend app that gets built and deployed through an external platform's
  own CI/build pipeline (Netlify, Cloudflare Pages, Vercel, etc.) — there is
  no shared image between dev and prod to keep in sync. The dev container's
  base image can be whatever's most convenient, including a full,
  non-minimal image, with zero production impact.

- **When production does run the same image built from the same
  Dockerfile** — a backend service, a database, anything containerised the
  same way in both environments, typically chosen specifically *for*
  dev/prod parity — letting dev and prod diverge on base image undermines
  that reason for using the same tooling at all. It risks exactly the
  failure shape from lesson 1: something a fuller dev image includes "for
  free" turns out to be missing in a minimal prod image, and surfaces for
  the first time in production instead of on a developer's machine.

**A common recurrence of the same root cause, worth watching for:** services
making outbound HTTPS calls need a CA trust store, and minimal/distroless
base images (`scratch`, `gcr.io/distroless/static`, Alpine without
`ca-certificates`, etc.) are a common way to ship small production images but
famously lack one unless it's explicitly installed or copied into the final
build stage. This is the exact same root cause as lesson 1, showing up
anywhere a minimal image meets TLS — not specific to Node or to VS Code.
Worth checking for deliberately whenever a new service's Dockerfile is
written, rather than discovering it via a failed outbound API call in
production.

**Working policy:** standard/larger images are a fine default for anything
where dev and prod never share an image. Where they do share an image, keep
dev and prod on the same base-image family on purpose, so a gap like this is
found locally, not in production.

# 4. Bake a non-root default user into dev container images

**Problem:** without an explicit `USER` in the Dockerfile, a container
defaults to `root` for *every* way it can be started — a plain `docker run`,
a bare `docker exec` with no `-u`, a tool that doesn't know to ask for a
different user. Anything created while one of those root sessions is active
— files in a bind-mounted source directory, or the initial content of a
freshly-seeded named volume — ends up owned by `root`. That then blocks
whatever non-root user (an editor's remote server, a later `npm install`,
etc.) actually needs to read or write those same files, producing permission
errors that reappear intermittently depending on which session happened to
touch a given path first.

Declaring a specific *remote user* in one tool's config (e.g. a
`remoteUser` setting) does not fix this — it only affects the one code path
that reads that config. Any other way of starting or entering the same
container is unaffected and can still default to root.

**Fix:** add a non-root user to the Dockerfile (most base images that expect
this usage already ship one, e.g. Node's official images provide a `node`
user) and switch to it explicitly:

```dockerfile
USER node
```

This makes that user the image's actual default, for any invocation,
closing off the entire class of "this particular tool forgot to ask for the
right user" problems at once, rather than patching each tool's own config
individually.

**A gotcha this doesn't fully solve on its own:** a *named volume* mounted
onto a path with no existing content in the image gets created fresh by
Docker as `root`-owned, regardless of the image's `USER`. This isn't
specific to any one path — it applies to *every* empty volume mount point,
and it bit the same project three separate times, on three different mounted
paths, before the pattern was recognised. The fix is the same each time:
pre-create the directory and `chown` it to the non-root user while still
root in the Dockerfile, *before* the `USER` switch, so that when Docker
seeds the empty volume from the image it copies that ownership across:

```dockerfile
RUN mkdir -p /path/that/will/be/a/volume \
	&& chown -R node:node /path/that/will/be/a/volume
USER node
```

Do this for every path a volume will be mounted onto, not just the first one
you happen to hit — the failure is generic to "empty volume, no prior
content to inherit ownership from," not tied to any particular directory.
