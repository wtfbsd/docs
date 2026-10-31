<!-- Copyright (c) 2026 The wtfbsd contributors. BSD-2-Clause (see LICENSE). -->

# Stage 7: operations: updates, new upstream releases, versions

[Index](README.md) · Previous: [Stage 6](06-release-and-publish.md)

After the first release you have three jobs: keep installed systems
patched, move to each new upstream release, and keep version numbers that
make upgrades work.

## Security updates

Because your base system is unmodified upstream and most packages come
from upstream, most security fixes reach users through upstream's own
channels. Your work is the part that is yours.

| | Base system | Upstream packages | Your packages |
|---|---|---|---|
| FreeBSD 16 | the template builds world from source, so the result is not byte-identical to upstream's binaries. The base system can also be installed as packages (`freebsd-base(7)`): upstream's `FreeBSD-base` repository (defined but disabled in `/etc/pkg/FreeBSD.conf`) is updated with `pkg upgrade -r FreeBSD-base`. If you use `src.conf` knobs, build your own base packages from the same source tree (`make packages` / `update-packages`, `build(7)`) and serve them from your repository. Otherwise, ship rebuilt images | `pkg upgrade` from the upstream repository | rebuild, publish, `pkg upgrade` |
| NetBSD 11.0 | the template unpacks upstream's release sets; apply upstream's security advisories as upstream describes them | `pkgin upgrade` (or `pkg_add -u`) | rebuild, re-index, publish |
| OpenBSD 8.0 | the base comes from the stock install sets, so `syspatch(8)` applies upstream's binary patches | `pkg_add -u` | rebuild, sign, publish |
| DragonFly 6.4.2 | rebuild from the release branch, or ship new images | `pkg upgrade` | rebuild, sign, publish |

The routine:

1. Watch upstream security advisories and the security lists of the
   ports systems (FreeBSD's VuXML is readable with `pkg audit -F` on a
   client).
2. For each advisory, check `ours.list`: does it affect a package you
   build? If yes, rebuild it now, publish, and let the publish trigger a
   media build.
3. If it affects something on the media, publish new media even if
   installed systems are already fixed through packages: new installs
   should start patched.
4. Say in the release notes which advisory a release fixes.

## Rolling to a new upstream release

Do it on a branch, as a new build, with the same gates as any release:

1. **Builders first.** Install or create a build host (or poudriere jail,
   `dsynth` host, OpenBSD build VM) for the new release, next to the old
   one. Keep the old one until the old release is end of life.
2. **Point the build at the new release.** FreeBSD: a `/usr/src` (or
   `-s DIR`) checkout of the new release. NetBSD: the new source tree
   (`-s DIR`) and the new pkgsrc binary repository in `PKG_PATH`.
   OpenBSD: `build.sh -r <new release>` (the site set name follows it,
   for example `site80.tgz` for 8.0), and the new stock install image on
   the media node. DragonFly: the new source tree and DPorts.
3. **Review `ours.list`.** Upstream may now ship what you patched or
   added; drop those entries. Rebuild every compiled package for the new
   ABI. Data and meta-packages usually only need a rebuild with the new
   ABI string.
4. **Open a new repository directory per ABI** (`FreeBSD:17:amd64/`,
   `11.0/`, `8.0/`). Client files that use `${ABI}` follow the upgrade
   on their own; the old directory stays for systems still on the old
   release.
5. **Check overlay assumptions.** rc variables, file locations and
   installer questions change between releases (the OpenBSD response file
   wording, DragonFly's `nrelease` targets). Run the dry run, then the full
   CI with installer and hardware stages.
6. **Release** as in [Stage 6](06-release-and-publish.md), with release
   notes that say what changed upstream and in your layers.

Lessons from doing this:

- Compare the version of the base the packages were built for with the
  version clients run. A package built for a newer base is **refused** by
  older clients ("wrong OS version"), for the whole repository.
- Verify the new builder reports the release you think it does (on
  FreeBSD, `freebsd-version -k -r -u` on the built system, and the
  version string poudriere recorded for the jail) before trusting its
  packages.
- Upgrade one builder at a time, and keep the previous one runnable so
  you can roll back.
- Look up the current releases every time. Do not trust a version
  number written in a document, including this one.

## Versions

Pick a scheme once and keep it:

- **Distribution version**: tie it to upstream and add your own
  revision, for example `ExampleBSD 16.0-1`, `16.0-2`, then `17.0-1`.
  Users can tell what they run from the name.
- **Build number**: the CI build number in every file name; it is what
  you publish and what a bug report quotes.
- **Your packages**: versions that only go up, with a date or counter
  first (`1.0.20261031.1`). A rebuilt package with the same version is
  never upgraded on clients.
- **Each image** carries a manifest of its inputs: upstream release,
  template commit, overlay commit, package versions.

## Keeping it running

- **Never let an empty variable reach a destructive command.** Guard
  every `rm` on a variable path; copy new, verify, then delete old.
- **Keep the previous release and repository tree** online for rollback.
- **Audit clients** occasionally: every installed system should have
  signature checking on for your repository (the repository file and the
  key are in the overlay; a system that predates them does not).
- **Use boot environments for upgrades where the system has them**
  (FreeBSD with ZFS: `bectl(8)`), so a bad upgrade boots back to the last
  good state.
- **Write down what you learned.** Every trap in this guide was found
  the hard way once. When you find a new one, add it to your fork's
  documentation in the same change that fixes it.
