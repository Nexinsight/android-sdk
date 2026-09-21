#!/usr/bin/env bash
# Publish nexinsight.aar and nexinsight-sources.jar to GitHub Packages as com.nexinsight:sdk.
#
# Usage:
#   GITHUB_ACTOR=<user> GITHUB_TOKEN=<token with write:packages> ./publish.sh [version]
#
# The version defaults to android:versionName from the AAR manifest.
set -euo pipefail

cd "$(dirname "$0")"

GROUP_ID="com.nexinsight"
ARTIFACT_ID="sdk"
REPO_URL="https://maven.pkg.github.com/Nexinsight/android-sdk"
AAR="nexinsight.aar"
SOURCES="nexinsight-sources.jar"

: "${GITHUB_ACTOR:?set GITHUB_ACTOR to your GitHub username}"
: "${GITHUB_TOKEN:?set GITHUB_TOKEN to a token with write:packages}"

VERSION="${1:-$(unzip -p "$AAR" AndroidManifest.xml | strings | sed -n 's/.*android:versionName="\([^"]*\)".*/\1/p' | head -1)}"
: "${VERSION:?could not determine version; pass it as the first argument}"

[ -f "$AAR" ] || { echo "missing $AAR" >&2; exit 1; }
[ -f "$SOURCES" ] || { echo "missing $SOURCES" >&2; exit 1; }

SETTINGS="$(mktemp)"
trap 'rm -f "$SETTINGS"' EXIT
cat > "$SETTINGS" <<EOF
<settings>
  <servers>
    <server>
      <id>github</id>
      <username>${GITHUB_ACTOR}</username>
      <password>${GITHUB_TOKEN}</password>
    </server>
  </servers>
</settings>
EOF

echo "Publishing ${GROUP_ID}:${ARTIFACT_ID}:${VERSION} to ${REPO_URL}"

mvn -B -s "$SETTINGS" deploy:deploy-file \
  -DrepositoryId=github \
  -Durl="$REPO_URL" \
  -DgroupId="$GROUP_ID" \
  -DartifactId="$ARTIFACT_ID" \
  -Dversion="$VERSION" \
  -Dpackaging=aar \
  -Dfile="$AAR" \
  -Dsources="$SOURCES" \
  -DgeneratePom=true \
  -Dname="Nexinsight Android SDK" \
  -Ddescription="Nexinsight event tracking SDK for Android"

echo "Done: ${GROUP_ID}:${ARTIFACT_ID}:${VERSION}"
