#!/bin/bash
set -e

# Ensure APT_GITHUB_TOKEN is set
if [ -z "$APT_GITHUB_TOKEN" ]; then
  echo "Error: No APT_GITHUB_TOKEN nor GH_PAT is set. Please set one in your Codespaces environment."
  exit 1
fi

SPEC="$1"

NAME=$(yq '.name' "$SPEC")
REPO=$(yq '.repo' "$SPEC")
MAJOR=$(yq '.major // ""' "$SPEC")
DESCRIPTION=$(yq '.description' "$SPEC")
PACKAGE_TYPE=$(yq '.package_type // "binary"' "$SPEC")
VERSION=$(bash scripts/fetch-latest-version.sh "$REPO" "$MAJOR")

echo "Processing $NAME ($REPO) version $VERSION with package_type: $PACKAGE_TYPE"

ARCHS=$(yq '.architectures | keys | .[]' "$SPEC")

# Fetch latest release information once
response_file=releases-latest.json
echo "Fetching release information for $REPO..."
curl -sH "Authorization: Bearer ${APT_GITHUB_TOKEN}" https://api.github.com/repos/$REPO/releases > ${response_file}

if [ ! -s "$response_file" ]; then
  echo "Error: Failed to fetch release information or no releases found for $REPO"
  exit 1
fi

for ARCH in $ARCHS; do
  echo "Processing architecture: $ARCH"

  if [ "$PACKAGE_TYPE" = "deb" ]; then
    # Handle .deb package type
    echo "  Using .deb package type for $ARCH"
    DEB_PATTERN=$(yq ".architectures.\"$ARCH\".deb_pattern" "$SPEC")

    if [ -z "$DEB_PATTERN" ] || [ "$DEB_PATTERN" = "null" ]; then
      echo "Error: deb_pattern is required for package_type 'deb' on architecture $ARCH"
      exit 1
    fi

    echo "  Using pattern: $DEB_PATTERN"

    # Find matching .deb asset
    asset_url=$(jq -r --arg pattern "$DEB_PATTERN" '
        .[]
        | select (.tag_name == "v'$VERSION'")
        | .assets[]
        | select(.name | test($pattern))
        | .url
    ' < ${response_file})

    asset_name=$(jq -r --arg pattern "$DEB_PATTERN" '
        .[]
        | select (.tag_name == "v'$VERSION'")
        | .assets[]
        | select(.name | test($pattern))
        | .name
    ' < ${response_file})

    if [ -z "$asset_name" ] || [ -z "$asset_url" ]; then
        echo "Error: Could not find a compatible .deb asset for architecture $ARCH with pattern: $DEB_PATTERN"
        echo "Available assets for version v$VERSION:"
        jq -r '.[] | select(.tag_name == "v'$VERSION'") | .assets[] | .name' < ${response_file} || echo "  No assets found"
        exit 1
    fi

    echo "  Found matching asset: $asset_name"

    # Download .deb file directly
    mkdir -p "pool/$NAME"
    echo "  Downloading .deb package..."
    curl -sL \
         -H "Accept: application/octet-stream" \
         -H "Authorization: Bearer ${APT_GITHUB_TOKEN}" \
         -o "pool/$NAME/${NAME}_${VERSION}_${ARCH}.deb" \
         "${asset_url}"

    echo "  Downloaded .deb package: $asset_name -> pool/$NAME/${NAME}_${VERSION}_${ARCH}.deb"

  else
    # Handle binary package type (default/existing behavior)
    echo "  Using binary package type for $ARCH"
    RAW_URL=$(yq ".architectures.\"$ARCH\".url" "$SPEC")
    BIN_PATH=$(yq ".architectures.\"$ARCH\".bin_path" "$SPEC")
    SELECTOR=$(yq ".architectures.\"$ARCH\".selector" "$SPEC")

    if [[ -z "$SELECTOR" || "$SELECTOR" = "null" ]]; then
      SELECTOR=$ARCH
    fi

    echo "  Using selector: $SELECTOR"
    URL=$(echo "$RAW_URL" | sed "s/\${VERSION}/$VERSION/g")

    WORKDIR=$(mktemp -d)
    mkdir -p "$WORKDIR/$NAME-$VERSION/usr/bin"
    mkdir -p "$WORKDIR/$NAME-$VERSION/DEBIAN"

    POSTINST=$(yq '.postinst // ""' "$SPEC")
    if [ -n "$POSTINST" ]; then
      echo "$POSTINST" > "$WORKDIR/$NAME-$VERSION/DEBIAN/postinst"
      chmod +x "$WORKDIR/$NAME-$VERSION/DEBIAN/postinst"
    fi

    asset_url=$(jq -r --arg os "Linux" --arg arch "$SELECTOR" '
        .[]
        | select (.tag_name == "v'$VERSION'")
        | .assets[]
        | select(.name | test($os; "i") and test($arch; "i"))
        | .url
    ' < ${response_file})

    asset_name=$(jq -r --arg os "Linux" --arg arch "$SELECTOR" '
        .[]
        | select (.tag_name == "v'$VERSION'")
        | .assets[]
        | select(.name | test($os; "i") and test($arch; "i"))
        | .name
    ' < ${response_file})

    if [ -z "$asset_name" ] || [ -z "$asset_url" ]; then
        echo "Error: Could not find a compatible release asset for Linux $SELECTOR."
        echo "Available assets for version v$VERSION:"
        jq -r '.[] | select(.tag_name == "v'$VERSION'") | .assets[] | .name' < ${response_file} || echo "  No assets found"
        exit 1
    fi

    echo "  Found matching asset: $asset_name"

    echo "  Downloading and extracting archive..."
    curl -sL \
         -H "Accept: application/octet-stream" \
         -H "Authorization: Bearer ${APT_GITHUB_TOKEN}" \
         -o "$WORKDIR/archive" \
         "${asset_url}"

    mkdir "$WORKDIR/extracted"
    tar -xf "$WORKDIR/archive" -C "$WORKDIR/extracted"

    if [ ! -f "$WORKDIR/extracted/$BIN_PATH" ]; then
        echo "Error: Binary not found at expected path: $BIN_PATH"
        echo "Available files in archive:"
        find "$WORKDIR/extracted" -type f | head -20
        exit 1
    fi

    cp "$WORKDIR/extracted/$BIN_PATH" "$WORKDIR/$NAME-$VERSION/usr/bin/$NAME"
    chmod +x "$WORKDIR/$NAME-$VERSION/usr/bin/$NAME"

    cat > "$WORKDIR/$NAME-$VERSION/DEBIAN/control" <<EOF
Package: $NAME
Version: $VERSION
Section: utils
Priority: optional
Architecture: $ARCH
Maintainer: Fabio Mora <code@fabiomora.dev>
Description: $DESCRIPTION
EOF

    echo "  Building .deb package..."
    mkdir -p "pool/$NAME"
    dpkg-deb \
      --build "$WORKDIR/$NAME-$VERSION" \
      "pool/$NAME/${NAME}_${VERSION}_${ARCH}.deb"

    echo "  Built binary package: ${NAME}_${VERSION}_${ARCH}.deb"
  fi
done

rm -f $response_file
