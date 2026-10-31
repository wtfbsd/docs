<!-- Copyright (c) 2026 The wtfbsd contributors. BSD-2-Clause (see LICENSE). -->

# Stage 4: packages, upstream first, plus a small repository of your own

[Index](README.md) · Previous: [Stage 3](03-build-media.md) · Per-OS commands: [Stage 4b](04b-packages-per-os.md) · Next: [Stage 5: CI](05-ci.md)

## The rule

**Use the upstream project's binary packages for everything you can.
Build and host only what is unique to your distribution.**

Your users' systems point at two repositories:

1. the **upstream** binary repository for the release (FreeBSD's official
   pkg repository, the pkgsrc binary packages for NetBSD, OpenBSD's
   packages, the DPorts binary repository for DragonFly);
2. a **small, signed product repository** of your own, holding only the
   packages that justify being yours.

Upstream builds, tests and publishes security fixes for thousands of
packages. Every package you rebuild yourself is one you now have to
rebuild for every one of those fixes. A small product repository is
cheap to keep current; a full mirror of upstream with your name on it is
a second ports project.

## Upstream or ours: decide per package

For every package your images or users need, ask one question: **is the
upstream binary package, exactly as upstream builds it, what we want?**
If yes, it is **upstream**: name it in a `packages.list` and do nothing
else. If no, it is **ours** only for one of these reasons:

| Reason | Example |
|--------|---------|
| `product` | content that only you have: `examplebsd-artwork`, `examplebsd-firstboot`, default settings, helper scripts |
| `meta` | a meta-package with no files that depends on upstream packages: `examplebsd-desktop` pulling Xorg, Xfce, LightDM and the drivers |
| `patched` | an upstream package with a fix upstream has not shipped yet (send the fix upstream too, and drop yours when it lands) |
| `options` | an upstream port built with non-default options |
| `missing` | software upstream does not package at all (consider contributing the port upstream) |

Anything without one of those reasons comes from upstream. "We want to
control the version" and "it was easier to build everything" are not
reasons.

Write the decisions down in your `<slug>-ports` repository, one line per
self-hosted package, with its reason:

```
# ours.list: every package the product repository publishes, and why
examplebsd-artwork      product   wallpapers, logos, greeter theme
examplebsd-desktop      meta      pulls the desktop from upstream
examplebsd-firstboot    product   first-boot account helper
```

The publish step refuses to publish a package that is not in this list,
and CI refuses a line without a reason. See the check at the end.

## Keep "ours" small

- **Prefer data and meta-packages.** A package of files (artwork,
  configuration, scripts) or of dependencies only has no compiled code,
  so it never breaks when upstream bumps a shared library. Most of a
  distribution's identity fits in packages like these.
- **Name your packages after your slug** (`examplebsd-<thing>`), so they
  can never collide with an upstream name by accident.
- **Do not republish upstream dependencies.** Building your package also
  builds its dependencies; publish only the packages in `ours.list`, and
  let the dependencies resolve from upstream. Republishing dependencies
  caused "wrong OS version" refusals on clients in practice.
- **Build compiled packages against the same ports branch as the
  upstream repository you consume** (on FreeBSD: the quarterly branch for
  the quarterly repository, the main branch for latest), and rebuild them
  whenever upstream moves, so the libraries they link against match.
- **Put configuration that can change in a package, not in the overlay**
  (see [Stage 2](02-overlays-and-profiles.md)), but keep the package
  small: one concern per package.
- **Review `ours.list` at every upstream release.** A `patched` or
  `missing` entry that upstream has caught up with is deleted.
- **Version your packages monotonically** (a date or build counter first,
  for example `1.0.20261031.1`). Package tools compare versions, not
  hashes: a package rebuilt under the same version is never upgraded.

## Overriding an upstream package

For `patched` and `options` packages you keep upstream's name, so that
other packages' dependencies still resolve to it. Then the client must
prefer your repository for that name:

| OS | How the product repository wins |
|----|---------------------------------|
| FreeBSD, DragonFly | `PRIORITY` in the repository file: "Higher values are preferred. Default: 0" (`pkg.conf(5)` on both systems), so give the product repository a priority above 0. `CONSERVATIVE_UPGRADE` (on by default) keeps a package upgrading from the repository it was installed from, which can override the priority for a package already installed from upstream. Test with `pkg rquery '%n-%v %R' <name>` and `pkg install -n <name>` |
| NetBSD | no priority setting. `pkgin` fetches a package found in two repositories from the one listed first in `repositories.conf` ("order matters"), so list the product repository first. `pkg_add` searches the `PKG_PATH` entries (separated by semicolons) with no priority. Simplest: avoid same-name overrides |
| OpenBSD | no priority setting. `pkg_add` searches `TRUSTED_PKG_PATH`, then `PKG_PATH` (entries separated by colons); `/etc/installurl` is used only when neither is set, unless `PKG_PATH` names the special entry `installpath`. With `-u`, every package of the same stem anywhere in `PKG_PATH` is a candidate and only newer versions are taken, so an override must carry a higher version. It must also be signed by a key in `/etc/signify/` the client trusts (by default any `*pkg` key) |

Wherever priority is weak, prefer a renamed package (`examplebsd-foo`)
that conflicts with the upstream one over a same-name override.

## Serving the repository

Any static HTTPS web server works. Package clients only fetch files.

- **Layout** (FreeBSD and DragonFly): `https://pkg.example.org/${ABI}/latest/`
  with the `pkg repo` catalogue (`meta.conf`, `packagesite.pkg`,
  `data.pkg`) next to `All/`. NetBSD: one directory of `.tgz` files plus
  `pkg_summary.gz`. OpenBSD: one directory of signed `.tgz` files per
  release and architecture.
- **HTTPS only.** Signatures prove who made a package; TLS keeps the
  metadata private and stops trivial tampering with downloads.
- **Publish atomically.** Build the new tree in a fresh directory, verify
  it, then switch a `latest` symlink to it. Keep the previous tree for
  rollback. Never rewrite the live catalogue in place while clients fetch.
- **One writer.** Exactly one job may write or re-sign the catalogue.
  Serialise it with a lock (for example `lockf(1)` on a fixed lock file).
  Media jobs only read the published repository.
- **Every green package build is published.** A successful build whose
  packages never reached the repository is unfinished work, and your
  media will ship stale packages.
- **Never torrent packages or catalogues.** Torrents are for large media
  only.

## Keys

- Generate the signing key on the host that signs, and keep the private
  key there (and in an offline backup). It never goes in git, never on a
  build agent, never in a CI workspace, never in a container image.
- Sign on the signing host. Builders hand it finished packages; the
  signing step pulls exactly the files of this build from a path the
  build user cannot write.
- Put the **public** key (or fingerprint) in your overlay, so every image
  trusts your repository from its first boot. Downloading the key from
  the same server as the packages is trust on first use: a substituted
  key and repository verify perfectly.
- Plan rotation: ship the next public key in an update before you start
  signing with it.

## Client configuration lives in the overlay

`overlay/base/rootfs/` carries the repository file(s) and the public key,
so the installed system and every later update use upstream plus your
repository. The upstream repository file is left as upstream ships it; you
add a file next to it. The exact files per OS are in
[Stage 4b](04b-packages-per-os.md).

## How media builds pull from both

The media build must install packages from **the same two repositories
your users get**, configured from the same files the overlay ships:

- FreeBSD: a repository configuration directory holding the upstream and
  product repository files, passed to pkg (`pkg -R DIR -r STAGE install`).
- NetBSD: `PKG_PATH` listing the product repository and the upstream one.
- OpenBSD: `PKG_PATH` for `install.site`, or packages carried on the
  media for offline installs.
- DragonFly: the template builds the listed origins from DPorts with
  `dsynth`; the product repository is used by the installed system.

Rebuild the media whenever your packages change, and whenever a
security fix lands upstream for a package on the media. A media build is
a snapshot: it does not pick up later packages by itself.

## Check that it worked

From a clean client (a VM booted from your image), not from the build
host:

1. Refresh the catalogues, and confirm the product repository lists the
   packages you published, with the ABI and version you built:
   FreeBSD/DragonFly `pkg update -f && pkg rquery -a -r ExampleBSD '%n-%v'`.
   A signing mismatch can show up as an **empty** repository with exit
   status 0, so check the count, not the exit status.
2. `pkg install -n examplebsd-desktop` (or the OS equivalent) resolves
   every dependency from upstream.
3. **The self-hosted check:** list every package in the product
   repository and compare with `ours.list`. Fail when a published package
   is not listed, when a line has no reason from the table above, or when
   a published package is identical in name and version to the upstream
   one (it should come from upstream).
