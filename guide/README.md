<!-- Copyright (c) 2026 The wtfbsd contributors. BSD-2-Clause (see LICENSE). -->

# The ecosystem playbook: make and ship your own BSD

This guide takes you from nothing to your own BSD distribution, with
its own name, its own installer media, its own package repository and
its own release site. It is built on unmodified upstream FreeBSD, NetBSD,
OpenBSD or DragonFly, using the wtfbsd templates.

The running example is **ExampleBSD** (slug `examplebsd`). Every host
name is a placeholder under `example.org`.

An AI agent can do the whole thing for you: the matching agent skill is
`skills/make-your-own-distro/SKILL.md` in
[wtfbsd/agents](https://github.com/wtfbsd/agents). This guide is the
human version of the same stages.

## The stages

| # | Stage | You end with |
|---|-------|--------------|
| 1 | [Fork and name](01-fork-and-name.md) | `product.conf` and four repositories under your org |
| 2 | [Overlays and profiles](02-overlays-and-profiles.md) | your files and package lists on top of unmodified upstream |
| 3 | [Build media](03-build-media.md) | images and ISOs per profile, with all firmware inside |
| 4 | [Packages: upstream first](04-packages.md) | a decision per package: upstream's, or one of a few of your own |
| 4b | [Packages per OS](04b-packages-per-os.md) | a small, signed product repository served over HTTPS |
| 5 | [CI](05-ci.md) | Jenkins builds, boots, installs and tests every change |
| 6 | [Release and publish](06-release-and-publish.md) | signed checksums, `latest.json`, release notes, a site |
| 7 | [Operations](07-operations.md) | security updates, new upstream releases, versions |

## Supported bases

| Base | Release | Root filesystem | Build host |
|------|---------|-----------------|------------|
| FreeBSD | 16 | ZFS or UFS | FreeBSD |
| NetBSD | 11.0 | FFS (ZFS for data pools only) | any POSIX host for the base and the image; NetBSD for the package step |
| OpenBSD | 8.0 | FFS | OpenBSD |
| DragonFly | 6.4.2 | HAMMER2 or UFS | DragonFly |

Always build on the latest upstream release, and check the version again
when you start: releases move faster than documents. FreeBSD 16 is,
as this is written, the development branch (16-CURRENT): there is no
16.0-RELEASE on download.freebsd.org yet, and the newest release is 15.1.

## The principles

1. **Decorate, do not fork.** Your distribution is upstream plus layers of
   your own files and packages. Never patch the upstream source or ports
   tree.
2. **Upstream packages first.** Consume the upstream binary repository
   for everything you can. Build and host only what is unique to you:
   your own packages, meta-packages, and the few upstream packages you
   must patch or build differently.
3. **Layers stack in one order**: upstream, baseline, product, packages.
   A product layer only adds.
4. **Everything is in the image.** Firmware for every supported device is
   installed at build time. Nothing downloads at install or first boot.
5. **Test the media you ship**, the way users use it: boot the ISO,
   install, reboot from disk, log in. On real hardware for what a VM
   cannot prove.
6. **Machines do the work.** CI builds and tests everything unattended.
   Every green package build is published; every package change rebuilds
   the media.
7. **Keys stay home.** Private signing keys live on the signing host and
   nowhere else. Public keys ship in the overlay.

## What the templates do today, and what you add

The templates build images, apply overlays, install package lists, boot
images in bhyve and check for a login prompt. These pieces are described
in this guide but are **not yet in the templates**; your fork adds them:

- the firmware coverage gate (Stage 3);
- building, signing and serving your product package repository, and
  the repository files in the overlay (Stage 4);
- the greeter screenshot check, the installer end-to-end test and a
  real-hardware stage (Stage 5);
- the signed checksum file, `latest.json` and the site (Stage 6).
