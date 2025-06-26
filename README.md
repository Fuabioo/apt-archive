# APT Archive

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

## TODO

- [ ] Generate dynamically the specs
