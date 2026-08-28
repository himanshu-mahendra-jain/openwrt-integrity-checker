# OpenWrt Integrity Checker

Scripts to create known-good baselines and verify the integrity of OpenWrt routers.

The baseline script records selected system information, critical file hashes, installed packages, UID 0 accounts, SSH authorized keys, and cron configuration.

The verifier compares the current router state against the previously generated known-good baseline and reports detected differences.

The scripts support multiple OpenWrt routers and use an SSH key with `ssh-agent` authentication.

## Requirements

* Linux system with Bash
* Bash 4 or newer
* OpenSSH client
* SSH access to the OpenWrt routers
* Root SSH access to the OpenWrt routers
* OpenWrt using the `apk` package manager
* A known-good router state for baseline generation

The scripts currently expect the OpenWrt SSH private key at:

```text
~/.ssh/openwrt
```

## What It Checks

The baseline records:

* OpenWrt release information
* Running kernel information
* Critical file SHA-256 hashes
* Installed packages
* UID 0 accounts
* SSH authorized keys
* Cron configuration

The verifier compares the current router state against the stored baseline.

## Supported Routers

The scripts support multiple routers.

The default configuration contains:

```bash
ROUTERS=(
    "root@192.168.1.1"
    "root@192.168.1.2"
    "root@192.168.1.3"
)
```

Change these values to match the routers being monitored.

The addresses above are examples and are not required by the scripts.

## SSH Authentication

The scripts use:

```text
~/.ssh/openwrt
```

as the SSH private key.

An `ssh-agent` is started when the script runs and the key is loaded with:

```bash
ssh-add ~/.ssh/openwrt
```

The private-key passphrase therefore needs to be entered only once per script execution.

SSH connections explicitly use:

```text
-o IdentitiesOnly=yes
```

to ensure the configured OpenWrt key is used.

## Generate a Baseline

Make the script executable:

```bash
chmod +x routers-generate-baseline.sh
```

Run it:

```bash
./routers-generate-baseline.sh
```

A different baseline directory can be specified:

```bash
./routers-generate-baseline.sh ./my-baseline
```

The routers should be in a known-good state before generating a baseline.

## Baseline Directory

The default baseline directory is:

```text
./known-good/
```

Each router receives its own directory:

```text
known-good/
├── router-1/
│   ├── authorized_keys
│   ├── crontabs.txt
│   ├── files.sha256
│   ├── packages.txt
│   ├── system.txt
│   └── uid0.txt
├── router-2/
│   └── ...
└── router-3/
    └── ...
```

The baseline contains information specific to the monitored routers and should normally not be committed to a public repository.

## System Information

The baseline records:

```text
/etc/openwrt_release
uname -a
```

This allows the verifier to detect changes to the OpenWrt release or running kernel.

## Critical File Hashes

The baseline generates SHA-256 hashes for selected files under:

```text
/etc/config
/etc/init.d
/etc/rc.d
/etc/crontabs
/etc/dropbear
```

It also checks selected system files:

```text
/etc/passwd
/etc/shadow
/etc/group
/etc/hosts
/etc/rc.local
/etc/firewall.user
```

During verification, the current SHA-256 hashes are compared with the known-good baseline.

Missing files are also reported.

## Installed Packages

The baseline records the installed APK packages using:

```bash
apk list --installed
```

The package list is sorted before being stored.

During verification, the current package list is compared against the baseline.

Added or removed packages result in a failed check.

## UID 0 Accounts

The baseline records all accounts with UID `0` from:

```text
/etc/passwd
```

For example:

```text
root
```

Unexpected UID 0 accounts are detected during verification.

## SSH Authorized Keys

The baseline records authorized SSH keys from:

```text
/root/.ssh/authorized_keys
/etc/dropbear/authorized_keys
```

Changes to these files are reported by the verifier.

This can detect unauthorized additions or removals of SSH authentication keys.

The baseline stores public SSH keys, not the private key used by the verification scripts.

## Cron Persistence

The baseline records files under:

```text
/etc/crontabs/
```

Cron configuration is checked separately as a persistence mechanism.

Changes to cron jobs are reported during verification.

## Verify Router Integrity

Make the verifier executable:

```bash
chmod +x routers-integrity-checker.sh
```

Run it:

```bash
./routers-integrity-checker.sh
```

A different baseline directory can be specified:

```bash
./routers-integrity-checker.sh ./my-baseline
```

The verifier checks every configured router against its corresponding baseline.

## Verification Result

The verifier reports:

```text
PASS
FAIL
WARN
```

Example:

```text
========================================
 Overall Result
========================================

PASS: 18
FAIL: 0
WARN: 0

RESULT: ALL CHECKS PASSED
```

Exit codes are:

```text
0  All checks passed
1  Baseline incomplete or warnings
2  Modification detected
```

These exit codes can be used by automation or monitoring systems.

## Verification Process

For each router, the verifier performs:

```text
1. SSH connectivity
2. System information
3. Critical file hashes
4. Installed packages
5. UID 0 accounts
6. SSH authorized keys
7. Cron configuration
```

The six primary checks are reported individually, while cron is reported as a persistence check.

## Security Model

This project uses a **known-good baseline** model.

The basic assumption is:

```text
Known-good state
      ↓
Generate baseline
      ↓
Router changes
      ↓
Run integrity checker
      ↓
Compare against baseline
```

A difference indicates that the router state has changed.

A successful verification means that the checked data matches the stored baseline. It does **not** prove that the router is completely uncompromised.

If a baseline was generated after a compromise, the compromised state could become the new baseline.

For this reason, baselines should only be generated from routers whose state is trusted.

## Public Repository

The scripts can be safely published without publishing the router's private SSH key.

Do not commit:

```text
~/.ssh/openwrt
```

or other private keys.

The generated baseline should also normally remain outside the public repository because it may contain environment-specific information such as:

* Router configuration details
* Installed packages
* SSH public keys
* Cron jobs
* System information
* File hashes

Add the baseline directory to `.gitignore`:

```gitignore
known-good/
```

## Limitations

The current checks do not provide full filesystem or runtime integrity verification.

They do not currently detect every possible:

* Modified executable
* Kernel-level compromise
* Running malicious process
* Network-level compromise
* Persistence mechanism outside the checked locations
* Firmware modification
* Memory-only compromise

The project is intended as a lightweight baseline and change-detection tool rather than a complete intrusion-detection system.

## Project Files

The intended project layout is:

```text
.
├── README.md
├── routers-generate-baseline.sh
├── routers-integrity-checker.sh
├── .gitignore
└── known-good/
```

The `known-good/` directory should normally be generated locally and excluded from Git.

## License

This project is independent of the OpenWrt project.

OpenWrt is an independent open-source project. Refer to the upstream project for its licensing terms.

The source code for this project is licensed under the GNU General Public License v3.0 (GPLv3). See the LICENSE file for the full license terms.

If you fork or build upon this project, attribution to the original project is appreciated.
