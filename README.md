# gizmosql-install

One-line installer scripts for [GizmoSQL](https://github.com/gizmodata/gizmosql).
Served from <https://install.gizmosql.com> via GitHub Pages.

## Usage

**macOS &amp; Linux**

```bash
curl -fsSL https://install.gizmosql.com/install.sh | sh
# or, for the LTS channel:
curl -fsSL https://install.gizmosql.com/install.sh | sh -s -- --channel lts
```

**Windows (PowerShell)**

```powershell
iwr https://install.gizmosql.com/install.ps1 -OutFile install.ps1
.\install.ps1
# or, for the LTS channel:
.\install.ps1 -Channel lts
```

Pass `--help` (sh) or `Get-Help .\install.ps1` (ps1) for all options
(channel, version pin, install prefix, etc.).

## What's in here

| File         | Purpose                                                           |
|--------------|-------------------------------------------------------------------|
| `install.sh` | POSIX install script (macOS, Linux). Tested with `dash` and `bash`. |
| `install.ps1`| PowerShell install script (Windows 10+, PowerShell 5.1 / 7+).     |
| `index.html` | Friendly landing page served at <https://install.gizmosql.com/>.   |
| `CNAME`      | GitHub Pages custom domain.                                        |

The scripts download the matching release zip from
<https://github.com/gizmodata/gizmosql/releases>, optionally verify a
sibling `.sha256` file if published, and install
`gizmosql_server[_lts]` + `gizmosql_client[_lts]` to a writable prefix
(default `~/.local/bin` on POSIX, `%LOCALAPPDATA%\Programs\GizmoSQL`
on Windows).

## Hosting setup

- GitHub Pages enabled on the `main` branch.
- Custom domain `install.gizmosql.com` (CNAME record + `CNAME` file).
- TLS provisioned automatically by GitHub Pages via Let's Encrypt.

## License

Apache-2.0, matching the main GizmoSQL project.
