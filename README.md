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
| `.github/workflows/test-install.yml` | CI: runs the installers end-to-end on every supported platform. |
| `.github/scripts/e2e-test.*` | Shared smoke test: start `gizmosql_server`, connect with `gizmosql_client`, run a query. |

The scripts download the matching release zip from
<https://github.com/gizmodata/gizmosql/releases>, optionally verify a
sibling `.sha256` file if published, and install
`gizmosql_server[_lts]` + `gizmosql_client[_lts]` to a writable prefix
(default `~/.local/bin` on POSIX, `%LOCALAPPDATA%\Programs\GizmoSQL`
on Windows).

## CI: every platform, end to end

`.github/workflows/test-install.yml` runs both install scripts on native
runners for every supported platform/architecture:

| Platform        | Runner             |
|-----------------|--------------------|
| linux/amd64     | `ubuntu-latest`    |
| linux/arm64     | `ubuntu-24.04-arm` (same Debian-family arm64 as Raspberry Pi OS) |
| macos/arm64     | `macos-latest`     |
| windows/amd64   | `windows-latest`   |
| windows/arm64   | `windows-11-arm`   |

Each platform installs both channels (stable + LTS), then runs a true
end-to-end check: start `gizmosql_server`, connect with `gizmosql_client`,
and verify `SELECT 1` returns. It also asserts the installer UX: the PATH
hint, full-path "Get started" examples when the prefix is off PATH, and the
warning when an older copy (e.g. from Homebrew) shadows the new install.
A weekly scheduled run tests the latest release so breakage from a new
release or runner image is caught even when this repo is quiet.

### Gating GizmoSQL releases on these tests

The workflow is reusable (`workflow_call`) and accepts a `version` input, so
the `gizmodata/gizmosql` release pipeline can publish a release as a
**prerelease** (assets are public, but `releases/latest` ignores it), run
these installer tests against the candidate tag on all platforms, and only
then promote it to the latest release:

```yaml
  test-installers:
    if: startsWith(github.ref, 'refs/tags/')
    needs: [create-release]
    uses: gizmodata/gizmosql-install/.github/workflows/test-install.yml@main
    with:
      version: ${{ github.ref_name }}

  promote-release:
    if: startsWith(github.ref, 'refs/tags/')
    needs: [test-installers]
    runs-on: ubuntu-latest
    permissions:
      contents: write
    steps:
      - env:
          GH_TOKEN: ${{ github.token }}
        run: gh release edit "$GITHUB_REF_NAME" --repo "$GITHUB_REPOSITORY" --prerelease=false --latest
```

## Hosting setup

- GitHub Pages enabled on the `main` branch.
- Custom domain `install.gizmosql.com` (CNAME record + `CNAME` file).
- TLS provisioned automatically by GitHub Pages via Let's Encrypt.

## License

Apache-2.0, matching the main GizmoSQL project.
