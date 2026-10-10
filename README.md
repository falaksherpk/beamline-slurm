# beamline-slurm

Builds [Slurm](https://slurm.schedmd.com/) Debian packages for the beamline lab's HPC
cluster (`hpc-ctl`, `hpc-c1`, `hpc-gpu`; handbook Part 2, Chapter 18). This repository
holds no Slurm source: it pins one upstream release tarball by SHA-256 and builds it with
SchedMD's own `debian/` packaging, unchanged, in a clean Ubuntu 24.04 container.

| File | Purpose |
|---|---|
| `SHA256SUMS` | the one tarball this commit builds, and its SHA-256 |
| `SOURCE` | where the tarball comes from and how its hash was checked |
| `packaging/deb/Containerfile` | builder image: pinned `ubuntu:24.04` + generic build tools |
| `packaging/deb/build-deb.sh` | the build |

## Build (on `pkg.beamline`, as `falak`)

```bash
podman build -t localhost/beamline-slurm-builder:noble packaging/deb
packaging/deb/build-deb.sh ~/artifacts/slurm-26.05.4
```

The script refuses a dirty tree, a non-empty output directory and a tarball that fails
the pinned hash. It installs Slurm's Build-Depends from its own `debian/control` in a
throwaway container, builds as an unprivileged user and writes the `.deb`s, `.buildinfo`,
`.changes`, `SHA256SUMS` and `lintian.txt` to the output directory.

## Publish

Each `.deb` goes into the lab's signed apt repository with `beamline-publish deb FILE`
(handbook Ch15), as `falak` on `pkg.beamline`.

## Upgrading Slurm

Change `SHA256SUMS` and `SOURCE` together, after checking the new tarball against the
matching GitHub tag as recorded in `SOURCE`.

## Licence

The files in this repository are MIT-licensed (`LICENSE`). Slurm itself is GPL-2.0-or-later
and is not part of this repository.
