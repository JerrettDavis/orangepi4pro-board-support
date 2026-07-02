# Contributing

This repository owns Orange Pi 4 Pro board-support source: kernel fragments,
DTS workflow, touch/display fallback code, and validation tools.

## Rules

- Commit source, patches, config fragments, and docs. Do not commit built
  kernels, modules, DTBs, rootfs trees, or vendor source checkouts.
- Keep generated or private captures under `research/private/`.
- Record upstream source URL, branch, commit, and verification date for every
  patch set.
- Run `scripts/ci-checks.sh` before pushing.

