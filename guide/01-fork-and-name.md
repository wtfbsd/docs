<!-- Copyright (c) 2026 The wtfbsd contributors. BSD-2-Clause (see LICENSE). -->

# Stage 1: fork and name your distribution

[Index](README.md) · Next: [Stage 2: overlays and profiles](02-overlays-and-profiles.md)

You start with a few answers and end with four repositories under your own
GitHub organisation, plus a `product.conf` that every later stage reads.
The tooling lives in the
[wtfbsd/agents](https://github.com/wtfbsd/agents) repository.

## What you need

- A GitHub organisation or account you can create repositories in.
- The GitHub CLI (`gh`), logged in (`gh auth login`), for the fork step.
- A POSIX shell and `awk` for the scripts. No BSD host is needed yet.

## 1. Answer the questions

`questions.yaml` in wtfbsd/agents is the contract. Each question `id` is a
key in your `answers.yaml` and a key in the `product.conf` that comes out of
it. Ask an agent to walk you through it (see `AGENTS.md`), or write the file
yourself. The ten steps are:

| Step | Keys | What it decides |
|------|------|-----------------|
| Q1 | `DISTRO_OS` | `freebsd`, `netbsd`, `openbsd`, `dragonfly` (or `illumos`) |
| Q2 | `DISTRO_NAME`, `DISTRO_SLUG` | the name people see, and the lowercase slug used for repositories, files and paths |
| Q3 | `DISTRO_ARCH` | `amd64` or `aarch64` (the OS row decides what is allowed) |
| Q4 | `FILESYSTEM_ROOT`, `ZFS_DATA_POOL`, `ZFS_POOL_NAME` | the root filesystem and an optional ZFS data pool |
| Q5 | `PROFILE` | `desktop`, `appliance` or `both` |
| Q6 | `PACKAGE_SET` | `minimal`, `base-server`, `base-desktop` or `custom` |
| Q7 | `INSTALLER` | `tui` everywhere; `gui` only where the OS row allows it |
| Q8 | `MOTD`, `BRAND_COLOR`, `BRAND_URL` | one-line message of the day, an accent colour (`RRGGBB`), an `https://` URL |
| Q9 | `CI_ENABLED` | whether Jenkins builds it |
| Q10 | `PUBLISH_METHOD`, `PUBLISH_TARGET`, `PUBLISHER_ORG` | where releases are announced, and the org that owns the forks |

The `per_os` table in `questions.yaml` says what each OS can honestly do.
The short version: ZFS root on FreeBSD only (and illumos); ZFS data pools on
NetBSD but never as root; no ZFS at all on OpenBSD or DragonFly. When the
table and a wish disagree, the table wins.

A minimal `answers.yaml` (see `examples/` in wtfbsd/agents for full ones):

```yaml
DISTRO_OS: freebsd
DISTRO_NAME: ExampleBSD
DISTRO_SLUG: examplebsd
PROFILE: both
BRAND_URL: https://example.org
PUBLISH_TARGET: example.org
PUBLISHER_ORG: example-org
```

Keys you leave out take their default. `DISTRO_ARCH`, `FILESYSTEM_ROOT` and
`INSTALLER` default to the first entry of your OS row.

## 2. Produce product.conf

Run the scripts from a clone of wtfbsd/agents:

```sh
git clone https://github.com/wtfbsd/agents && cd agents
scripts/apply-answers.sh answers.yaml          # writes ./product.conf
scripts/apply-answers.sh -c answers.yaml       # check only, writes nothing
scripts/apply-answers.sh -o out/product.conf -f answers.yaml
```

What the script actually does:

- reads `questions.yaml` (from beside the script, or `-q FILE`) and your
  answers, with a deliberately small YAML reader (flat `KEY: value` lines);
- fills defaults, skips questions whose `required_if` gate is not met (for
  example `ZFS_POOL_NAME` when `ZFS_DATA_POOL` is `no`);
- checks every value against its choices, pattern and length;
- checks the combination against your OS row: architecture, root
  filesystem, installer and ZFS pool support;
- warns about odd but legal mixes (a desktop package set on an appliance);
- prints a table of every key, its value and where the value came from;
- writes `product.conf` as single-quoted `KEY='value'` lines, safe to source
  from POSIX sh, and refuses to overwrite an existing file without `-f`.

Exit status: 0 valid, 2 usage error, 3 validation failure. Never hand-edit
`product.conf`: fix `answers.yaml` and run the script again. `answers.yaml`
holds no secrets, so it is fine to commit.

## 3. Fork the templates

```sh
scripts/fork-distro.sh --os freebsd --name ExampleBSD --slug examplebsd \
    --org example-org                  # dry run: prints the plan and the gh commands
scripts/fork-distro.sh --os freebsd --name ExampleBSD --slug examplebsd \
    --org example-org --apply          # does it
```

What the script actually does:

- validates the OS against the `per_os` rows of `questions.yaml`, the name
  (1 to 64 characters, no quotes, `$`, backquotes, backslashes or control
  characters), the slug
  (`^[a-z][a-z0-9-]*$`, 2 to 32 characters) and the org names;
- warns when the slug collides with template words (`ports`, `ci`, ...);
- by default prints the plan and stops. Nothing touches the network;
- with `--apply`, checks that `gh` is installed and logged in, refuses to
  run if any target repository already exists, then runs
  `gh repo fork <src> --fork-name <name> --org <org> --default-branch-only`
  four times and sets each fork's description with `gh repo edit`:

| Template | Your fork |
|----------|-----------|
| `wtfbsd/<os>-template` | `<org>/<slug>` (the product repository) |
| `wtfbsd/ports-templates` | `<org>/<slug>-ports` |
| `wtfbsd/installer-template` | `<org>/<slug>-installer` |
| `wtfbsd/ci-templates` | `<org>/<slug>-ci` |

`--template-org` forks from another org that holds the templates.

What it does **not** do: it does not clone the forks and it does not copy
`product.conf` into them. Clone the product repository and put
`product.conf` at its top yourself (or keep it as a CI artifact; see
[Stage 5](05-ci.md)). Exit status 3 means a fork or description failed;
existing forks make a re-run refuse, so delete or rename them first.

## 4. Choose the slug carefully

The slug is in repository names, image file names
(`<slug>-<profile>-<arch>.img`), install paths
(`/usr/local/share/<slug>/`), helper commands (`<slug>-install`), package
names (Stage 4) and repository names in client configuration. Changing it
later touches every one of those. Pick something short, lowercase, and
not the name of an existing project.

## 5. What a forker customises

Everything you change lives in your fork, never in the upstream system:

| What | Where (product repository) |
|------|-----------------------------|
| Files on the installed system | `overlay/base/rootfs/`, `overlay/profiles/<profile>/rootfs/` |
| Packages | `overlay/base/packages.list`, `overlay/profiles/<profile>/packages.list` |
| Drivers and firmware | the package lists (driver and firmware packages), see [Stage 3](03-build-media.md) |
| Base system knobs | `overlay/base/src.conf` (FreeBSD; `WITHOUT_` knobs only) |
| Branding | `MOTD`, `BRAND_COLOR`, `BRAND_URL` in answers; artwork under `/usr/local/share/<slug>/artwork/` delivered by your own package; `overlay/profiles/desktop/branding.conf` on FreeBSD |
| First-boot user | the `firstboot_user` rc script and its config file, see [Stage 2](02-overlays-and-profiles.md) |
| Profiles | which of `desktop` / `appliance` you build, and what each adds |
| Your own package repository | client configuration in `overlay/base/rootfs/`, see [Stage 4](04-packages.md) |

Placeholders in overlay files (`@DISTRO_NAME@`, `@SLUG@`, `@MOTD@`,
`@BRAND_URL@`, and on NetBSD `@ZFS_POOL_NAME@`) are filled in by `build.sh`
from `product.conf`. A file whose name contains `@SLUG@` is renamed to your
slug.

## Check that it worked

- `scripts/apply-answers.sh -c answers.yaml` exits 0.
- `gh repo view <org>/<slug>` (and the three others) succeeds.
- In a clone of `<org>/<slug>`: `./build.sh -c product.conf -n` prints a
  build plan and exits 0. That dry run works on any POSIX host.
