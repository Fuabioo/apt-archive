# APT Archive 🗃️

```
apt-archive/
├── .github/
│   └── workflows/
│       └── build.yml
├── scripts/
│   ├── wrap-to-deb.sh
│   ├── fetch-latest-version.sh
│   ├── build-repo.sh
│   ├── load-gpg-profile.sh
│   └── dev-container.sh
├── specs/
│   └── foobar.yml
├── pool/
│   └── foobar/   # debs are generated here
├── dists/        # signed repo metadata is generated here
├── README.md
```

## Local Development

For local testing, the Docker container automatically generates ephemeral GPG keys. Just run:

```sh
docker compose run --build --rm --remove-orphans build
```

The container will:
1. Generate a temporary GPG key pair (valid for 30 days)
2. Set `GPG_KEY_ID` and `GPG_PRIVATE_KEY` environment variables automatically
3. Build and sign the APT repository using the ephemeral key

⚠️ **Warning**: The auto-generated GPG keys are ephemeral and for testing only. Never use them in production.

## Production Setup

For production, you need to provide your own GPG keys:

```.env
GPG_KEY_ID=1234567890ABCDEF
GPG_PRIVATE_KEY=LS0tLS1CRUdJTi...
```

To generate production GPG keys:

```sh
# Generate a new GPG key
gpg --full-generate-key

# Get the key ID (last 16 characters of fingerprint)
gpg --list-secret-keys --keyid-format LONG

# Export private key as base64
gpg --armor --export-secret-keys YOUR_KEY_ID | base64 -w 0
```

Copy `.env.example` to `.env` and fill in your production values.

## Spec Format

The APT archive generator supports two package types:

### Binary Packages (Default)

For packages distributed as archives containing binaries:

```yaml
name: example-tool
repo: owner/repo-name
package_type: binary  # optional, this is the default
description: "Example binary package"
major: 1  # optional, filter by major version
architectures:
  amd64:
    url: https://github.com/owner/repo-name/releases/download/v${VERSION}/tool_linux_amd64.tar.gz
    bin_path: path/to/binary/in/archive
    selector: amd64  # optional, defaults to architecture key
  arm64:
    url: https://github.com/owner/repo-name/releases/download/v${VERSION}/tool_linux_arm64.tar.gz
    bin_path: path/to/binary/in/archive
postinst: |  # optional post-installation script
  #!/bin/bash
  echo "Package installed successfully"
```

### Deb Packages

For packages already distributed as .deb files:

```yaml
name: example-tool
repo: owner/repo-name
package_type: deb
description: "Example pre-built .deb package"
major: 1  # optional, filter by major version
architectures:
  amd64:
    deb_pattern: ".*[_-](amd64|x86_64)[_-].*\\.deb$"
  arm64:
    deb_pattern: ".*[_-](arm64|aarch64)[_-].*\\.deb$"
  armv7:
    deb_pattern: ".*[_-](armv7|armhf)[_-].*\\.deb$"
```

The `deb_pattern` field uses regex to match the correct .deb file from GitHub release assets. Common patterns:
- `.*_amd64\\.deb$` - matches files ending with `_amd64.deb`
- `.*linux.*amd64.*\\.deb$` - matches files containing "linux" and "amd64"
- `.*[_-](amd64|x86_64)[_-].*\\.deb$` - matches various amd64/x86_64 naming conventions

## TODO

- [ ] Generate dynamically the specs
