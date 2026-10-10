#!/usr/bin/env bash
# Build SchedMD's Slurm .debs from the pinned upstream tarball in a clean, throwaway
# container (handbook Ch18; same pattern as beamline-healthcheck's Ch15 build-deb.sh).
# Usage: packaging/deb/build-deb.sh OUTDIR
# Needs the builder image: podman build -t localhost/beamline-slurm-builder:noble packaging/deb
set -euo pipefail

image=localhost/beamline-slurm-builder:noble
cache=${XDG_CACHE_HOME:-$HOME/.cache}/beamline-slurm
url_base=https://download.schedmd.com/slurm
out=${1:?usage: $0 OUTDIR}

repo=$(git rev-parse --show-toplevel)
cd "$repo"
if [[ -n $(git status --porcelain --untracked-files=no) ]]; then
  echo "refusing: tracked files have uncommitted changes; the build follows HEAD's SHA256SUMS" >&2
  exit 1
fi
if ! podman image exists "$image"; then
  echo "refusing: builder image $image not found" >&2
  exit 1
fi

# The one tarball this commit pins, from the committed SHA256SUMS.
sums=$(git show HEAD:SHA256SUMS)
if [[ $(wc -l <<< "$sums") -ne 1 || ! $sums =~ ^[0-9a-f]{64}\ \ (slurm-[0-9.]+\.tar\.bz2)$ ]]; then
  echo "refusing: SHA256SUMS must hold exactly one line '<sha256>  slurm-X.Y.Z.tar.bz2'" >&2
  exit 1
fi
tarball=${BASH_REMATCH[1]}
srcdir=${tarball%.tar.bz2}

mkdir -p "$out"
out=$(realpath "$out")
if [[ -n $(ls -A "$out") ]]; then
  echo "refusing: $out is not empty" >&2
  exit 1
fi

# Download once into the cache; never use a file that fails the pinned hash.
mkdir -p "$cache"
if [[ ! -e $cache/$tarball ]]; then
  echo "=== downloading $url_base/$tarball"
  curl -fsSL -o "$cache/$tarball.part" "$url_base/$tarball"
  mv "$cache/$tarball.part" "$cache/$tarball"
fi
if ! (cd "$cache" && sha256sum -c --strict <<< "$sums"); then
  echo "refusing: $cache/$tarball does not match the pinned SHA-256 (left in place for inspection)" >&2
  exit 1
fi

echo "=== building $srcdir (beamline-slurm $(git rev-parse --short HEAD)) in $image -> $out"
# Inside: root installs the Build-Depends from Slurm's own debian/control, the
# unprivileged 'ubuntu' user builds, root copies the results to /out. lintian runs after
# the copy and writes its findings to /out/lintian.txt; an error there fails the build
# but leaves the packages for inspection.
podman run --rm -i -e "TARBALL=$tarball" -e "SRCDIR=$srcdir" \
  -v "$cache/$tarball:/in/$tarball:ro" -v "$out:/out" "$image" bash -euo pipefail -c '
    tar -xjf "/in/$TARBALL" -C /build
    chown -R ubuntu:ubuntu /build
    apt-get update -qq
    apt-get build-dep -y -qq --no-install-recommends "/build/$SRCDIR"
    cd "/build/$SRCDIR"
    runuser -u ubuntu -- env DEB_BUILD_OPTIONS="parallel=$(nproc)" dpkg-buildpackage -b -us -uc
    cd /build
    cp ./*.deb ./*.buildinfo ./*.changes /out/
    (cd /out && sha256sum -- *.deb > SHA256SUMS)
    rc=0
    runuser -u ubuntu -- lintian --fail-on error --info ./*.changes > /out/lintian.txt 2>&1 || rc=$?
    echo "lintian exit: $rc (findings in lintian.txt: $(grep -c "^[EW]: " /out/lintian.txt) E/W lines)"
    exit "$rc"
  '
echo "=== results"
ls -l "$out"
