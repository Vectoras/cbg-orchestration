# Overview

A multi-app product for a small charity, backed by a single source of truth. A Go
backend and a self-hosted PostgreSQL database hold the book inventory; two
separate frontend applications consume it.

The project serves two purposes at once: it is a real production deployment for
the charity, and it is a portfolio piece (a first substantial Go project).

# This Repo

Docker Compose setup that wires the backend, database, and frontends together
for local development and deployment. No application code lives here — see the
sibling `backend`, `website`, and `staff` repos for that.
