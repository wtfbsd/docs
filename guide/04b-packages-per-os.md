<!-- Copyright (c) 2026 The wtfbsd contributors. BSD-2-Clause (see LICENSE). -->

# Stage 4b: build, sign and serve your packages, per OS

[Index](README.md) · Policy: [Stage 4](04-packages.md) · Next: [Stage 5: CI](05-ci.md)

Read [Stage 4](04-packages.md) first: you build only the packages in
`ours.list`, and everything else comes from upstream. The host name
`pkg.example.org` and the paths below are placeholders.

Where a flag is marked "check", confirm it in the named manual page on
the release you ship before you rely on it.

## FreeBSD 16

### Build

**Data and meta-packages** need no ports tree. Stage the files, write a
manifest, and create the package with `pkg create`:

```sh
# stage/ holds usr/local/share/examplebsd/artwork/... ;
# meta/ holds +MANIFEST (UCL), plist is a pkg-plist style file list
pkg create -m meta/ -p plist -r stage -o out/
```

`-p plist` only works together with `-m DIR`. With `-M FILE` instead,
the manifest itself must list the files, and `-p` is not accepted
(`pkg-create(8)`, pkg 2.8). The manifest keys `pkg-create(8)` documents
are `name`, `version`, `origin`, `comment`, `desc`, `arch`, `www`,
`maintainer`, `prefix`, `deps` and the file entries; set `abi` (for
example `FreeBSD:16:amd64`) as well. Upstream packages of
architecture-independent ports carry the ABI `FreeBSD:16:*`, so a data
package can use that. A meta-package lists its upstream dependencies in
`deps` and installs no files.

**Compiled packages** (`patched`, `options`, `missing`) are built with
poudriere, from your own ports as an **overlay** on an unmodified ports
tree:

```sh
poudriere jail -c -j 160amd64 -v 16.0-RELEASE -a amd64
poudriere ports -c -p default                      # unmodified ports tree
poudriere ports -c -p examplebsd -m null -M /path/to/examplebsd-ports
poudriere bulk -j 160amd64 -p default -O examplebsd -f /path/to/ours.origins
```

`-v` takes a release name such as `16.0-RELEASE`; until FreeBSD 16.0 is
released there is none to download, so either build for the newest
release or create the jail from a source checkout (`-m git+https -v
main`, see `poudriere-jail(8)`). `ours.origins` holds the
`category/port` origins of the compiled packages in `ours.list`, one
per line, and `-f` needs an absolute path. `-O` puts your ports tree
over the default one without editing it. Use the ports branch that
matches the upstream repository you consume (quarterly or latest).
Non-default options go in poudriere's per-jail `make.conf` or are set
with `poudriere options`.

To take upstream binary packages for the dependencies instead of
building them, run `poudriere bulk -b latest` (or `quarterly`; set
`PACKAGE_FETCH_BRANCH` and `PACKAGE_FETCH_URL` in `poudriere.conf`).
poudriere cannot see local patches or non-OPTIONS knobs, so put every
`patched` and `options` package in `PACKAGE_FETCH_BLACKLIST`, or it may
fetch upstream's build in place of yours (`poudriere-bulk(8)`).

poudriere's package directory accumulates every package it ever built,
dependencies included. Publish **only** the packages named in
`ours.list`, from this run (the bulk log's list of built packages says
which), into a fresh publish directory.

### Sign

Make an RSA key once, on the signing host:

```sh
umask 077
openssl genrsa -out /root/keys/examplebsd-repo.key 4096
openssl rsa -in /root/keys/examplebsd-repo.key -pubout -out examplebsd-repo.pub
```

Build the signed catalogue over the publish directory:

```sh
pkg repo /srv/pkg/FreeBSD:16:amd64/20261031 /root/keys/examplebsd-repo.key
```

The key argument may carry a signer type, `rsa:KEYFILE`, `ecdsa:KEYFILE`
or `eddsa:KEYFILE` (pkg 2.8). Instead of a key file, `signing_command:
ssh signing-host sign.sh` sends only the catalogue hash to a signing
host, so the key never leaves it. The two modes are **not**
interchangeable: a key file pairs with `signature_type: "pubkey"` on the
client, a signing command with `signature_type: "fingerprints"` and a
`trusted/` fingerprint directory (`pkg-repo(8)`). poudriere can sign
its own repository with `PKG_REPO_SIGNING_KEY` in `poudriere.conf`, but
then poudriere needs the private key, which is exactly what you are
keeping off the builder; its `SIGNING_COMMAND` setting uses the signing
host instead.

`pkg repo` is not a verification tool: every run rewrites the
catalogue, and a run without the key argument writes it unsigned
(`-l` only adds a `files.pkg` listing). Verify from a client instead.

### Serve

```
/srv/pkg/FreeBSD:16:amd64/20261031/      meta.conf, packagesite.pkg, data.pkg, All/
/srv/pkg/FreeBSD:16:amd64/latest -> 20261031
```

### Client

Ship this in `overlay/base/rootfs/usr/local/etc/pkg/repos/ExampleBSD.conf`,
and the public key at the path it names. Leave `/etc/pkg/FreeBSD.conf`
alone: the upstream repository stays enabled.

```
ExampleBSD: {
  url: "https://pkg.example.org/${ABI}/latest",
  signature_type: "pubkey",
  pubkey: "/usr/local/etc/pkg/keys/examplebsd-repo.pub",
  enabled: yes,
  priority: 10
}
```

`priority` lets the product repository win for the few same-name
packages you override: higher values are preferred, and upstream keeps
the default of 0 (`pkg.conf(5)`). On FreeBSD 16, `/etc/pkg/FreeBSD.conf`
defines the upstream repositories `FreeBSD-ports` and
`FreeBSD-ports-kmods` (kernel module packages), plus `FreeBSD-base`,
disabled by default.

Media builds: copy `/etc/pkg/FreeBSD.conf` and the file above into one
directory and run the template's package step as
`pkg -R that-directory -r STAGE install -y ...`. `-R` replaces the
normal search path, so both files must be there. The `pubkey` path must
exist on the build host too.

## NetBSD 11.0

### Build

Upstream pkgsrc binary packages exist for NetBSD 11.0 (pkgsrc names the
amd64 architecture `x86_64`). Build only your own packages:

- **Your own packages** live in a category directory of your own (for
  example `examplebsd/examplebsd-desktop`) in your `<slug>-ports`
  repository. Adding a directory to a pkgsrc checkout is not patching
  pkgsrc; editing upstream package Makefiles is.
- Build one package with `make package` in its directory; it lands in the
  pkgsrc `packages/All/` directory. For many packages, use pbulk
  (`pkgtools/pbulk`) with a limited package list; check the pbulk
  documentation in pkgsrc for the list setting.
- Non-default options: `PKG_OPTIONS.<package>=` in `mk.conf`.

### Index

`pkgin` reads a `pkg_summary` file next to the packages:

```sh
cd /srv/pkgsrc/x86_64/11.0/All
for p in *.tgz; do pkg_info -X "$p"; done | gzip -9 > pkg_summary.gz
```

### Sign

pkg_install can sign packages with X.509 or GPG:
`pkg_admin x509-sign-package PKG SIGNED_PKG KEY CERT` or
`pkg_admin gpg-sign-package PKG SIGNED_PKG` (`pkg_admin(1)`). Clients
enforce signatures with `VERIFIED_INSTALLATION` in `pkg_install.conf`:
`never` (the default), `always`, `trusted` (prompt for unsigned
packages) or `interactive`; any value but `never` also needs
`CERTIFICATE_ANCHOR_PKGS` (`pkg_install.conf(5)`). The setting is
global, with no per-repository exception, so `always` would also refuse
upstream's binary packages unless they are signed by a certificate you
trust: decide how you configure that before you turn it on.

### Client

- `pkgin`: `/usr/pkg/etc/pkgin/repositories.conf`, one URL per line.
  List your repository first: a package that both repositories hold is
  fetched from the first one listed. Upstream's is
  `https://cdn.netbsd.org/pub/pkgsrc/packages/NetBSD/x86_64/11.0/All`.
- `pkg_add`: `PKG_PATH` with both locations, separated by a semicolon
  (`pkg_install.conf(5)`).

Ship both in `overlay/base/rootfs/`. The template's build uses `PKG_PATH`
for the image; set it to the same two locations.

## OpenBSD 8.0

### Build

- Put your own ports under `/usr/ports/mystuff/<category>/<port>`: the
  ports tree reserves that directory for local ports, so you never edit
  upstream ports.
- Build one with `make package` in its directory, or many with `dpb(1)`
  (`/usr/ports/infrastructure/bin/dpb`), passing your list of paths.
- Build natively on OpenBSD 8.0, for each architecture you ship.

### Sign

OpenBSD packages are signed with `signify(1)`. Make a key pair named
after the release:

```sh
signify -G -n -c "examplebsd 8.0 packages" \
    -p examplebsd-80-pkg.pub -s examplebsd-80-pkg.sec
```

Sign the built packages with `pkg_sign(1)`:

```sh
pkg_sign -C -s signify2 -s /path/to/examplebsd-80-pkg.sec \
    -o signed/ -S unsigned/
```

`-S` is the directory of unsigned packages, `-o` the output directory,
and `-C` adds the packages' checksums to `SHA256` there. The name of the
private key becomes the package's `@signer`, which is how `pkg_add`
finds the matching `/etc/signify/examplebsd-80-pkg.pub`. The private key
stays on the signing host.

### Serve

One directory per release and architecture, for example
`https://pkg.example.org/openbsd/8.0/packages/amd64/`, holding the
signed `.tgz` files.

### Client

- Put `examplebsd-80-pkg.pub` in `/etc/signify/` through the site set.
  `pkg_add` finds the key named in the package's signature there; by
  default it trusts any key whose name ends in `pkg`, so keep that
  suffix.
- Upstream packages come from `/etc/installurl` (`installurl(5)`) only
  while `PKG_PATH` is unset. To use both, name upstream with the special
  entry `installpath`:
  `PKG_PATH=https://pkg.example.org/openbsd/8.0/packages/amd64/:installpath`
  (entries are separated by colons and searched in order; `pkg_add(1)`).

The template's `install.site` runs `pkg_add` after the installer has
brought the network up, so packages come from the network at install
time. For an offline install, carry the packages (yours and the upstream
ones you need) on the media and point `PKG_PATH` at that local directory
in `install.site`.

## DragonFly 6.4.2

DragonFly uses the same `pkg` tool as FreeBSD, so the catalogue, the
signing and the client file work the same way.

### Build

- The template builds its package origins from the DPorts tree with
  `dsynth` during the release. For your own repository, run `dsynth` on
  a DragonFly build host. `dsynth` reads one ports tree
  (`Directory_portsdir` in `/etc/dsynth/dsynth.ini`, made by
  `dsynth init`) and has no overlay option, so add your ports as a
  category directory of your own inside a DPorts checkout (adding a
  directory is not patching DPorts). Build them with
  `dsynth build <origins>`; `dsynth rebuild-repository` rebuilds the
  catalogue (`dsynth(1)`).

### Sign

`dsynth` has no signing setting: it runs `pkg repo` without a key. Sign
the publish directory afterwards with `pkg repo DIR KEYFILE`, as on
FreeBSD, on the signing host.

### Client

Ship `overlay/base/rootfs/usr/local/etc/pkg/repos/ExampleBSD.conf` with the
same shape as the FreeBSD file (`url`, `signature_type`, `pubkey`,
`enabled`, `priority`). The upstream DPorts repository file
(`/usr/local/etc/pkg/repos/df-latest.conf`) stays as it is.
DragonFly's `pkg.conf(5)` documents `PRIORITY` the same way as FreeBSD's
(higher wins, default 0).

## Check that it worked (all systems)

On a VM booted from your media:

1. The product repository answers over HTTPS and its signature verifies
   (no "no trusted public keys" message; the package count is what you
   published).
2. Each package in `ours.list` installs; its dependencies come from
   upstream.
3. Nothing in the product repository is missing from `ours.list`, and
   every line of `ours.list` has a reason.
