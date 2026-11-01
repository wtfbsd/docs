<!-- Copyright (c) 2026 The wtfbsd contributors. BSD-2-Clause (see LICENSE). -->

# Stage 8: security: how to work, and what the product ships

[Index](README.md) · Previous: [Stage 7](07-operations.md)

This page is written for an AI agent that is building a distribution for
a user. It has three parts: [how to work](#part-1-how-to-work) on every
repository of the product, [what the product ships](#part-2-what-the-product-ships),
and [the `SECURITY.md`](#part-3-a-securitymd-in-every-repository) each
repository carries.

The practices come from FreeBSD, NetBSD, OpenBSD, DragonFly and illumos.
The templates do not yet set most of Part 2: the user's fork adds it,
and each section ends with the check that proves it.

Where this page says **check**, run the command on the installed system
and use what it prints. Defaults change between releases; do not write a
default into release notes that you have not seen on the system.

## Part 1: how to work

### Sweep for the class after every finding

A security bug is one instance of a class: an unquoted variable, a
temporary file with a predictable name, a parser that trusts its input.
When you fix one, search every repository of the product for the same
class the same day, fix every instance, and add a check to the tests
(a `grep`, a lint rule, a test case) that fails if the class comes back.
The fix is not done until that check exists and is red on the old code.

### An independent review for anything that runs as root or handles secrets

Installer code, first-boot scripts, `rc` scripts, package install
scripts, CI steps that hold credentials, and anything that touches a
signing key get a security review by a reviewer that did not write the
change: another agent, session or model, or a person. Give the reviewer
the code and a written threat model, not your conclusion.

The threat model answers, in a few lines each:

- What does this run as, and what can it reach (disks, keys, network)?
- Where does each input come from, and who can change it?
- What happens if each input is hostile: too long, empty, a path with
  `..`, a value with quotes, newlines or `$(...)`?
- What must never happen (an erased wrong disk, a leaked key, code run
  from input)?

### Sign-off is explicit

No change merges without a recorded review. Silence is not review.
Answer every finding in the commit message or the pull request: taken,
or not taken with the evidence. A change tagged as a security fix gets
its own security review before it merges, even when it is small.

### Static analysis and shellcheck

Run a secret scanner and a static analyser on every change, and
`shellcheck` on every shell script (`shellcheck -s sh` for `/bin/sh`
scripts, `-s ksh` for OpenBSD `ksh`). Run them from the repository's
tests so CI fails on a finding. A finding you decide to keep gets an
inline suppression with the reason, never a blanket exclusion.

Keep these out of every script, and make the tests fail if one appears:

| Do not | Do instead |
|---|---|
| `eval`, or `sh -c "$value"` with input | a `case` on the allowed values |
| unquoted `$var` in a command | `"$var"`; `set -eu` at the top |
| `curl ... \| sh` | download, verify the checksum or signature, then run |
| `mktemp` without a template, or a fixed `/tmp` name | `mktemp -d /tmp/name.XXXXXX`, removed by a `trap` |
| `awk -v x="$untrusted"` (escapes are interpreted) | pass the value in the environment and read `ENVIRON["x"]` |
| `python3 script` on a path that runs as root | `python3 -I`, so the current directory and the environment cannot inject modules |
| `rm -rf "$dir/"*` with a variable that may be empty | `: "${dir:?}"` first |

### Fuzz the parsers that run as root

Every file a root process parses is an attack surface: the installer's
answers and plan files, the first-boot configuration, `product.conf`,
`answers.yaml`. Give each parser a fuzz or property test: generated
input with quotes, newlines, `$(...)`, `../`, NUL bytes, very long and
empty values. The test passes only if the parser rejects bad input with
an error, never runs any of it, and never writes outside its target.
For Python parsers use a coverage-guided fuzzer such as atheris; for
shell parsers, a test that feeds the generated cases one by one.

### A standing audit, file by file

Apart from reviewing changes, read the code that already exists. Keep
a rota: one repository a week, every file read in full, oldest audit
first. Record each audit in `audit-log.md` in the user's docs
repository: the date, the repository and commit, the files read, and
each finding with where it was fixed. A finding starts a class sweep.

### Fix first, then disclose

A reported vulnerability is fixed privately, released, and then
published as an advisory. See [Part 3](#part-3-a-securitymd-in-every-repository).

## Part 2: what the product ships

### Only the services the profile needs

An installed system runs only what its profile needs: on a desktop, the
display manager and what the user's applications require; on an
appliance, `sshd` and the services it exists for. Write the expected
listening sockets per profile into the overlay, with a reason for each,
and have the boot test compare them with what the installed system
listens on. An extra socket fails the test.

| BSD | Enabled services | Listening sockets |
|---|---|---|
| FreeBSD 16 | `service -e` | `sockstat -46l` |
| NetBSD 11.0 | `/etc/rc.conf` against `/etc/defaults/rc.conf` | `sockstat -l` |
| OpenBSD 8.0 | `rcctl ls on` | `netstat -an -f inet`, `netstat -an -f inet6` |
| DragonFly 6.4.2 | `/etc/rc.conf` against `/etc/defaults/rc.conf` | `sockstat -46l` |
| illumos | `svcs` | `netstat -an -f inet`, `netstat -an -f inet6` |

### FreeBSD 16

**The installer's hardening menu.** `bsdinstall` offers a list of
hardening options; the script is `/usr/libexec/bsdinstall/hardening`.
Read it on the release you build: it names each option and the file it
writes. The settings behind it include:

| Setting | Where | Effect |
|---|---|---|
| `security.bsd.see_other_uids=0` | `sysctl.conf` | users see only their own processes |
| `security.bsd.see_other_gids=0` | `sysctl.conf` | the same, by group |
| `security.bsd.see_jail_proc=0` | `sysctl.conf` | users do not see processes in other jails |
| `security.bsd.unprivileged_read_msgbuf=0` | `sysctl.conf` | `dmesg` needs root |
| `security.bsd.unprivileged_proc_debug=0` | `sysctl.conf` | users cannot debug processes, not even their own |
| `kern.randompid=1` | `sysctl.conf` | random process IDs |
| `clear_tmp_enable="YES"` | `rc.conf` | `/tmp` is emptied at boot |
| `syslogd_flags="-ss"` | `rc.conf` | `syslogd` opens no network socket |
| `security.bsd.allow_destructive_dtrace=0` | `loader.conf` | no destructive DTrace |

Offer the menu in the user's installer, or set the settings in the
overlay. Propose these on by default for every profile: random PIDs,
clearing `/tmp`, no `syslogd` socket, no unprivileged `dmesg`, no
destructive DTrace. Propose hiding other users' processes on the
appliance. Leave unprivileged debugging allowed on a desktop for a
developer. Do not mark the console insecure while root is locked: no
one could then log in in single-user mode.

**securelevel.** `kern_securelevel_enable="YES"` and `kern_securelevel="1"`
in `rc.conf`. At 1, system-immutable flags cannot be cleared and kernel
modules cannot be loaded once it is raised. Offer it for the appliance.
On a desktop, check first that every driver loads before it is raised:
after boot, run `kldstat`, then plug in the devices a user adds later.
Check the running level with `sysctl kern.securelevel`.

**ASLR, PIE, stack protector, W^X.** Check, and record the result in the
release notes:

- `sysctl kern.elf64.aslr` (ASLR for 64-bit programs, and for PIE)
- `sysctl kern.elf64.allow_wx kern.elf64.nxstack` (writable and
  executable mappings; non-executable stack)
- `readelf -h /bin/sh | grep Type` (`DYN` means the base is built as PIE)
- `readelf -s /bin/sh | grep __stack_chk` (built with the stack protector)
- `elfctl /usr/local/bin/<program>` (a program's own opt-outs)

If ASLR is off, turn it on in `sysctl.conf`, boot the desktop and run
the user's applications. A program that fails gets `elfctl -e +noaslr`
on that program only, with the reason in the overlay.

**Capsicum** for programs you write in C: enter capability mode with
`cap_enter(2)` after opening what the program needs, and limit each
descriptor with `cap_rights_limit(2)`. See `capsicum(4)`.

**Daily package audit.** `pkg audit -F` fetches the vulnerability
database and lists installed packages with known vulnerabilities. `pkg`
installs a daily security script for it; check its switch and default
with `grep -h pkgaudit /usr/local/etc/periodic/security/*`, and
`/etc/periodic.conf` for an override. Its report goes to root's mail, which no one reads on a
desktop: alias root to the installed user in `/etc/mail/aliases`.

### NetBSD 11.0

**PaX.** Check `sysctl security.pax`: `aslr.global`, `mprotect.global`
and `segvguard.global` show whether ASLR, W^X (MPROTECT) and Segvguard
apply to all programs. Turn on what is off in `/etc/sysctl.conf`, and
give a program that fails its own exception with `paxctl(8)`, recorded
in the overlay with the reason.

**Curtain.** With the curtain on, users see only their own processes
and sockets. Check its name on the release with
`sysctl -a | grep curtain` (`security.models.extensions.curtain`, or
`security.curtain`) and set it to 1 in `/etc/sysctl.conf`. Propose it
for every profile.

**per_user_tmp.** `per_user_tmp=YES` in `/etc/rc.conf` gives each user
a private `/tmp` (check the variable in `/etc/defaults/rc.conf`).
Propose it for the desktop, then check that the
display manager and the desktop start and that the user's applications
find their sockets.

**Veriexec.** `veriexecgen(8)` writes fingerprints of the programs to
`/etc/signatures`; `veriexec=YES` in `/etc/rc.conf` loads them, and the
strict level decides what an unknown or changed program may do. The
fingerprints must be regenerated after every update, so offer it for
the appliance, not the desktop. See `security(7)` and `veriexecctl(8)`.

**securelevel.** Check `sysctl kern.securelevel` on an installed system
in multi-user mode. If it is below 1, set `securelevel=1` in
`/etc/rc.conf` for the appliance.

**Daily package audit.** `pkg_admin fetch-pkg-vulnerabilities` fetches
the list and `pkg_admin audit` checks installed packages against it.
The daily scripts can do both: check `fetch_pkg_vulnerabilities` in
`/etc/defaults/daily.conf` and `check_pkg_vulnerabilities` in
`/etc/defaults/security.conf`, and turn on in `/etc/daily.conf` and
`/etc/security.conf` whatever is off.

### OpenBSD 8.0

OpenBSD's defaults are the strongest of these systems: W^X, ASLR, PIE,
the stack protector, `pledge(2)` and `unveil(2)` in base, few services,
and securelevel 1. Keep all of them. Do not add `wxallowed` to any
mount, and do not turn off any default; check what the stock install
already has with `mount | grep wxallowed` and `sysctl kern.securelevel`.

**pledge and unveil in what you write.** A program you write for
OpenBSD calls `pledge(2)` with only the promises it needs and
`unveil(2)` with only the paths it reads or writes. In Perl, use
`OpenBSD::Pledge` and `OpenBSD::Unveil` from base. A shell script cannot
pledge: keep root shell scripts short and have them call pledged
programs.

**syspatch and packages.** `syspatch -c` lists the binary patches not
yet installed; `syspatch` installs them. It works because the base comes
from the stock install sets. Ship a daily job that runs `syspatch -c`
and `pkg_add -u -n` and tells the user when either has something to
install. OpenBSD has no package vulnerability database: fixes arrive as
package updates through `pkg_add -u`.

### DragonFly 6.4.2

**securelevel.** `kern_securelevel_enable="YES"` and `kern_securelevel="1"`
in `rc.conf`; offer it for the appliance and check with
`sysctl kern.securelevel`.

**ASLR and the rest.** DragonFly offers less than the others here.
Check what the kernel has with `sysctl -a | grep -iE 'random|aslr|nx'`
and `sysctl -a | grep '^security\.'`, and say in the release notes what
is and is not there.

**Daily package audit.** `pkg audit -F`, as on FreeBSD. Check the daily
security script's switch with
`grep -h pkgaudit /usr/local/etc/periodic/security/*`.

### illumos

**Least privilege.** Run each service with only the privileges it needs:
give it a user and a privilege set in its SMF manifest
(`method_credential`), not root. See what a process holds with
`ppriv -S <pid>`, and the privileges with `privileges(7)`. Give
administrators rights profiles and `pfexec` rather than a root shell.

**Zones.** Run network services in a non-global zone (`zonecfg(8)`,
`zoneadm(8)`), so a compromised service does not reach the global zone.

**Security flags.** Check what a process runs with using `psecflags <pid>`;
`security-flags(7)` lists the flags (ASLR among them) and how to set
the system default.

**Package audit.** It depends on the distribution's packaging: with
pkgsrc, `pkg_admin audit` as on NetBSD; with IPS, `pkg update -n` lists
the updates waiting.

### The build-time audit of the image's package set

Before the media is written, audit the exact set of packages installed
into the image root, and fail the build on a known vulnerability:

| BSD | Command, with the image root in `$ROOT` |
|---|---|
| FreeBSD 16, DragonFly 6.4.2 | `pkg audit -F $(pkg -r "$ROOT" query '%n-%v')` |
| NetBSD 11.0 | `pkg_admin fetch-pkg-vulnerabilities`, then `pkg_admin audit-pkg $(pkg_info -K "$ROOT/usr/pkg/pkgdb" \| awk '{print $1}')`; fail if it prints anything |
| OpenBSD 8.0 | no database: compare the image's packages with the newest on the mirror for the release, and list the release's errata since the install sets were cut |
| illumos | the distribution's command from the section above, against the image root |

When a vulnerability has no fix yet and the user accepts it, list it in
the overlay in an allowlist: the package, the advisory, the reason and a
review date. The build prints every allowed entry, and fails once the
date has passed. Say in the release notes what is allowed and why.

## Part 3: a SECURITY.md in every repository

The `SECURITY.md` for every wtfbsd repository is
[`templates/SECURITY.md`](../templates/SECURITY.md): report privately through GitHub's private vulnerability reporting; the
report is confirmed, fixed, released, and published as an advisory with
a CVE and credit to the reporter; `main` is the supported branch.

Give every repository of the user's product the same file:

1. Copy it into each
   fork, or once into the user's `.github` repository, which GitHub uses
   for every repository in the org that has no file of its own.
2. Put the user's maintainer address from the interview in the contact
   line, and move that line out of its comment, for reporters who cannot
   use GitHub.
3. Turn on private vulnerability reporting in each repository:
   `gh api -X PUT repos/<org>/<repo>/private-vulnerability-reporting`.
   Check with `gh api repos/<org>/<repo>/private-vulnerability-reporting`:
   it must print `"enabled":true`.
4. *Show the user* the file and the check.

## Check that it worked

- `sh tests/run-tests.sh` in each repository runs `shellcheck` and the
  class checks, and fails on a planted bad line.
- Each parser that runs as root has a fuzz or property test.
- The boot test fails on a listening socket that is not in the
  profile's list.
- The installed system shows the hardening you chose (the **check**
  commands above), and the release notes record it.
- A build with a package known to be vulnerable fails.
- Every repository has `SECURITY.md`, and private vulnerability
  reporting reports `"enabled":true`.
