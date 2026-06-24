#!/usr/bin/env bash
set -euo pipefail

# Version: prefer explicit override (manual trigger), fall back to git tag
if [ -n "${NOTIFY_VERSION:-}" ]; then
    VERSION="$NOTIFY_VERSION"
    git show "v${VERSION}:RELEASE_NOTES.md" > /tmp/release_notes.md 2>/dev/null \
        && NOTES_FILE="/tmp/release_notes.md" \
        || NOTES_FILE="RELEASE_NOTES.md"
else
    VERSION="${GITHUB_REF_NAME#v}"
    NOTES_FILE="RELEASE_NOTES.md"
fi

# Detect release type from section headers
TYPE=""
grep -q "^### Added"   "$NOTES_FILE" && TYPE="${TYPE:+$TYPE / }feature"
grep -q "^### Fixed"   "$NOTES_FILE" && TYPE="${TYPE:+$TYPE / }fix"
grep -q "^### Changed" "$NOTES_FILE" && TYPE="${TYPE:+$TYPE / }update"
grep -q "^### Removed" "$NOTES_FILE" && TYPE="${TYPE:+$TYPE / }cleanup"
[ -z "$TYPE" ] && TYPE="update"

# Fetch all recent CurseForge files once
CF_API_RESPONSE=$(curl -s \
  -H "x-api-key: ${CF_API_KEY}" \
  "https://api.curseforge.com/v1/mods/1445627/files?pageSize=50&sortOrder=desc")

# Search by version string in both fileName and displayName
CF_FILE_ID=$(echo "$CF_API_RESPONSE" | jq -r --arg ver "$VERSION" '
  [ .data[]?
    | select(
        (.fileName    // "" | contains($ver)) or
        (.displayName // "" | contains($ver))
      )
  ] | first | .id // ""')

# If version search found nothing, fall back to the newest file
if [ -z "$CF_FILE_ID" ] || [ "$CF_FILE_ID" = "null" ]; then
    CF_FILE_ID=$(echo "$CF_API_RESPONSE" | jq -r '.data[0].id // ""')
fi

# Build URLs — fall back to the addon page if file ID still unresolvable
if [ -n "$CF_FILE_ID" ] && [ "$CF_FILE_ID" != "null" ]; then
    CF_URL="https://www.curseforge.com/wow/addons/gse-tracker/files/${CF_FILE_ID}"
else
    CF_URL="https://www.curseforge.com/wow/addons/gse-tracker"
fi
GH_URL="https://github.com/${GITHUB_REPOSITORY:-LarryThiessen/GSE_Tracker}/releases/tag/v${VERSION}"

# Format notes: pull ONLY the current version's section (between "## $VERSION"
# and the next "## " heading), then its bullets — auto-bold key terms.
NOTES=$(awk -v ver="## $VERSION" '$0==ver{f=1;next} /^## /{f=0} f' "$NOTES_FILE" \
  | grep "^- " \
  | sed \
      -e 's/^- /• /' \
      -e 's/GSE/**GSE**/g' \
      -e 's/GS:E/**GS:E**/g' \
      -e 's/GSE Tracker/**GSE Tracker**/g' \
      -e 's/Blizzard/**Blizzard**/g' \
  | sed '$!G')   # blank line between bullets for breathing room

# Closing signature block, appended to the bottom of the embed description.
# NOTE: standard emoji must be real unicode (webhooks don't expand :shortcodes:).
# Custom server emoji must be <:name:ID>; the three below use temporary unicode
# placeholders until the real IDs are dropped in.
FOOTER_BLOCK=$(cat <<'EOF'
Enjoy,
**ScaryLarryGames!**
> 📥 **[Download](https://www.curseforge.com/wow/addons/gse-tracker)** | 💻 **[GitHub](https://github.com/LarryThiessen/GSE_Tracker)** | 🐞 **[Bug Reports](https://github.com/LarryThiessen/GSE_Tracker/issues)**
> 🧡 **[Patreon](https://www.patreon.com/ScaryLarryGames646)** | ☕ **[Ko-Fi!](https://ko-fi.com/scarylarrygames)** | 📕 **[SLG-Zygor's Affiliate!](https://zygorguides.com/ref/ScaryLarryGames/)** | 🪙 **Donations@Thrall**
EOF
)

DESCRIPTION="${NOTES}

${FOOTER_BLOCK}"

# Header line — rendered as an H1 in the message content, above the embed card.
# :GSE_Tracker: is a custom server emoji; swap to <:GSE_Tracker:ID> once known.
POST_DATE=$(date -u +'%B %-d, %Y')
HEADER="# Update: ${POST_DATE} :GSE_Tracker: GSE: Tracker v${VERSION}"

# Gold #FFD100 = 16760576
PAYLOAD=$(jq -n \
  --arg  version "$VERSION" \
  --arg  type    "$TYPE" \
  --arg  notes   "$DESCRIPTION" \
  --arg  cf_url  "$CF_URL" \
  --arg  gh_url  "$GH_URL" \
  --argjson color 16760576 \
  --arg  header  "$HEADER" \
  '{
    username: "GSE: Tracker",
    content: $header,
    embeds: [{
      author: { name: "🔑  New Update Available" },
      title:  ("v" + $version + " — Now Live"),
      url:    $cf_url,
      color:  $color,
      thumbnail: { url: "https://raw.githubusercontent.com/LarryThiessen/GSE_Tracker/main/media/GSE_Tracker_Round.png" },
      description: $notes,
      footer:    { text: "World of Warcraft · GSE: Tracker" },
      timestamp: (now | todate)
    }]
  }')

# POST, capture HTTP status + body so failures are visible (curl -s alone
# returns exit 0 even on HTTP 4xx, which previously masked rejected embeds).
HTTP_CODE=$(printf '%s' "$PAYLOAD" \
  | curl -s -o /tmp/discord_resp.txt -w "%{http_code}" \
      -X POST "$DISCORD_WEBHOOK" \
      -H "Content-Type: application/json" \
      -d @-)

echo "Discord responded HTTP $HTTP_CODE"
echo "Response body: $(cat /tmp/discord_resp.txt)"

if [ "$HTTP_CODE" -lt 200 ] || [ "$HTTP_CODE" -ge 300 ]; then
    echo "::error::Discord rejected the notification (HTTP $HTTP_CODE)"
    exit 1
fi
