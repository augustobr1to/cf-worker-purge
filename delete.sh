#!/usr/bin/env bash
set -euo pipefail

# ─────────────────────────────────────────────────────────────────
# Usage:
#   ./delete.sh <CF_API_TOKEN> <ACCOUNT_ID> <PROJECT_NAME>
#
# Example:
#   ./delete.sh "tok_abc123" "a1b2c3d4" "my-pages-project"
# ─────────────────────────────────────────────────────────────────

CF_API_TOKEN="${1:?Usage: $0 <CF_API_TOKEN> <ACCOUNT_ID> <PROJECT_NAME>}"
ACCOUNT_ID="${2:?Missing ACCOUNT_ID}"
PROJECT_NAME="${3:?Missing PROJECT_NAME}"

# ── Colors ────────────────────────────────────────────────────────
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

# ── Check dependencies ────────────────────────────────────────────
for dep in curl jq; do
  if ! command -v "$dep" &>/dev/null; then
    echo -e "${RED}❌ Required tool '${dep}' is not installed.${RESET}"
    echo -e "   Install it with: ${BOLD}brew install ${dep}${RESET}"
    exit 1
  fi
done

# ── Check wrangler ────────────────────────────────────────────────
echo -e "${CYAN}🔍 Checking for wrangler...${RESET}"

if ! command -v wrangler &>/dev/null; then
  echo -e "${YELLOW}⚠️  wrangler is not installed.${RESET}"

  if command -v brew &>/dev/null; then
    echo -ne "${YELLOW}Homebrew detected. Install wrangler now? [y/N]: ${RESET}"
    read -r INSTALL_CONFIRM
    if [[ "$INSTALL_CONFIRM" =~ ^[Yy]$ ]]; then
      echo -e "${CYAN}📦 Installing wrangler via Homebrew...${RESET}"
      brew install cloudflare-wrangler
    else
      echo -e "${RED}❌ wrangler is required. Aborting.${RESET}"
      exit 1
    fi
  else
    echo -e "${RED}❌ Homebrew not found. Please install wrangler manually:${RESET}"
    echo -e "   ${BOLD}npm install -g wrangler${RESET}   or   ${BOLD}brew install cloudflare-wrangler${RESET}"
    exit 1
  fi
else
  WRANGLER_VERSION=$(wrangler --version 2>&1 | head -n1)
  echo -e "${GREEN}✅ wrangler found: ${WRANGLER_VERSION}${RESET}"
fi

export CLOUDFLARE_API_TOKEN="${CF_API_TOKEN}"

BASE_URL="https://api.cloudflare.com/client/v4/accounts/${ACCOUNT_ID}/pages/projects/${PROJECT_NAME}/deployments"
AUTH_HEADERS=(-H "Authorization: Bearer ${CF_API_TOKEN}" -H "Content-Type: application/json")

# ── Fetch production deployment ID ────────────────────────────────
echo -e "\n${CYAN}🔍 Fetching project info...${RESET}"
PROJECT_INFO=$(curl -s -X GET \
  "https://api.cloudflare.com/client/v4/accounts/${ACCOUNT_ID}/pages/projects/${PROJECT_NAME}" \
  "${AUTH_HEADERS[@]}")

SUCCESS=$(echo "$PROJECT_INFO" | jq -r '.success')
if [[ "$SUCCESS" != "true" ]]; then
  echo -e "${RED}❌ Failed to fetch project. Check your ACCOUNT_ID, PROJECT_NAME and API token permissions.${RESET}"
  echo "$PROJECT_INFO" | jq '.errors'
  exit 1
fi

PROD_DEPLOYMENT_ID=$(echo "$PROJECT_INFO" | jq -r '.result.canonical_deployment.id')
echo -e "${GREEN}✅ Production deployment (will be preserved): ${BOLD}${PROD_DEPLOYMENT_ID}${RESET}"

# ── Collect all deployments via pagination ────────────────────────
echo -e "\n${CYAN}📄 Collecting all deployments...${RESET}"
ALL_IDS=()
PAGE=1

while true; do
  RESPONSE=$(curl -s -X GET "${BASE_URL}?per_page=25&page=${PAGE}" "${AUTH_HEADERS[@]}")
  IDS=$(echo "$RESPONSE" | jq -r '.result[].id')
  COUNT=$(echo "$IDS" | grep -c . || true)

  if [[ "$COUNT" -eq 0 ]]; then
    break
  fi

  while IFS= read -r ID; do
    ALL_IDS+=("$ID")
  done <<< "$IDS"

  ((PAGE++))
done

# ── Filter out production deployment ──────────────────────────────
TO_DELETE=()
for ID in "${ALL_IDS[@]}"; do
  if [[ "$ID" != "$PROD_DEPLOYMENT_ID" ]]; then
    TO_DELETE+=("$ID")
  fi
done

TOTAL=${#TO_DELETE[@]}

if [[ "$TOTAL" -eq 0 ]]; then
  echo -e "${GREEN}✅ No deployments to delete. Project is already clean.${RESET}"
  exit 0
fi

# ── Preview: show what will be deleted ────────────────────────────
echo -e "\n${BOLD}${YELLOW}⚠️  The following ${TOTAL} deployment(s) will be permanently DELETED:${RESET}\n"
for ID in "${TO_DELETE[@]}"; do
  echo -e "   ${RED}✖  ${ID}${RESET}"
done

echo -e "\n${BOLD}Project  :${RESET} ${PROJECT_NAME}"
echo -e "${BOLD}Account  :${RESET} ${ACCOUNT_ID}"
echo -e "${BOLD}Preserved:${RESET} ${PROD_DEPLOYMENT_ID} (production)\n"

# ── Confirmation ──────────────────────────────────────────────────
echo -ne "${BOLD}${RED}Type YES to confirm deletion of ${TOTAL} deployment(s): ${RESET}"
read -r CONFIRM

if [[ "$CONFIRM" != "YES" ]]; then
  echo -e "${YELLOW}⚠️  Aborted. Nothing was deleted.${RESET}"
  exit 0
fi

# ── Delete via wrangler ───────────────────────────────────────────
echo -e "\n${CYAN}🗑️  Starting deletion...${RESET}\n"
DELETED=0
FAILED=0

for ID in "${TO_DELETE[@]}"; do
  echo -ne "   Deleting ${ID}... "
  if wrangler pages deployment delete "$ID" \
      --project-name "$PROJECT_NAME" \
      --force 2>/dev/null; then
    echo -e "${GREEN}✔ done${RESET}"
    ((DELETED++))
  else
    echo -e "${RED}✖ failed${RESET}"
    ((FAILED++))
  fi
  sleep 0.3
done

# ── Summary ───────────────────────────────────────────────────────
echo -e "\n${BOLD}──────────────────────────────────────────${RESET}"
echo -e "${GREEN}✅ Deleted  : ${DELETED}${RESET}"
[[ "$FAILED" -gt 0 ]] && echo -e "${RED}❌ Failed   : ${FAILED}${RESET}"
echo -e "${CYAN}⏭️  Preserved : 1 (production: ${PROD_DEPLOYMENT_ID})${RESET}"
echo -e "${BOLD}──────────────────────────────────────────${RESET}"
echo -e "\n🎉 You can now safely delete the project '${BOLD}${PROJECT_NAME}${RESET}' from the dashboard."