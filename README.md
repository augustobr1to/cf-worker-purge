
# delete.sh — Cloudflare Pages Bulk Deployment Cleaner

A shell script to bulk-delete all Cloudflare Pages deployments from a project,
solving the known issue where projects with more than 100 deployments cannot be
deleted from the dashboard or via API.

> **Reference:** [Cloudflare Pages Known Issues – Delete a project with a high number of deployments](https://developers.cloudflare.com/pages/platform/known-issues/#delete-a-project-with-a-high-number-of-deployments)

---

## Requirements

| Tool       | Notes                                           |
|------------|-------------------------------------------------|
| `bash` ≥ 4 | macOS ships with 3.x — run `brew install bash`  |
| `curl`     | Pre-installed on macOS                          |
| `jq`       | `brew install jq`                               |
| `wrangler` | Script offers to install via Homebrew if missing |

---

## Creating a Cloudflare API Token

### Step-by-step

1. Go to the [Cloudflare Dashboard](https://dash.cloudflare.com)
2. Click your profile icon (top right) → **My Profile**
3. Go to **API Tokens** → **Create Token**
4. Choose **Create Custom Token**
5. Fill in the token details:

   **Token name:**
   ```
   Pages Deployment Cleaner
   ```

   **Permissions — add the following two policies:**

   | Group     | Scope              | Permission |
   |-----------|--------------------|------------|
   | `Account` | Cloudflare Pages   | `Edit`     |
   | `Account` | Account Settings   | `Read`     |

   > `Account Settings: Read` is required to verify your account ID during API calls.
   > `Cloudflare Pages: Edit` grants full CRUDL access to list and delete deployments.

   **Account Resources:**
   ```
   Include → <your account name>
   ```

   **Client IP Address Filtering:** *(optional but recommended)*
   ```
   Add your current IP for extra security
   ```

6. Click **Continue to summary** → **Create Token**
7. **Copy the token immediately** — it is only shown once

### Minimum required policies (summary)

```
Account / Cloudflare Pages / Edit
Account / Account Settings  / Read
```

You do **not** need Zone-level permissions for this script.

---

## Setup

```bash
chmod +x delete.sh
```

---

## Usage

```bash
./delete.sh <CF_API_TOKEN> <ACCOUNT_ID> <PROJECT_NAME>
```

### Arguments

| Argument        | Where to find it                                             |
|-----------------|--------------------------------------------------------------|
| `CF_API_TOKEN`  | API token you created above                                  |
| `ACCOUNT_ID`    | Cloudflare Dashboard → right sidebar, under **Account ID**  |
| `PROJECT_NAME`  | Exact name of the Pages project (e.g. `my-pages-project`)   |

### Example

```bash
./delete.sh \
  "cfut_abc123yourtoken" \
  "a1b2c3d4e5f6youraccount" \
  "my-pages-project"
```

---

## What it does

1. **Checks dependencies** — verifies `curl` and `jq` are available
2. **Checks for `wrangler`** — if missing, detects Homebrew and offers to install it automatically
3. **Validates the project** — fetches project info and confirms the API token has access
4. **Identifies production** — reads `canonical_deployment.id` and marks it as preserved
5. **Collects all deployments** — paginates through the full list (25 per page)
6. **Previews deletions** — prints every deployment ID that will be removed before doing anything
7. **Asks for confirmation** — requires typing `YES` (case-sensitive) to proceed
8. **Deletes via `wrangler`** — runs `wrangler pages deployment delete --force` per deployment
9. **Reports summary** — shows deleted, failed, and preserved counts

---

## After the script

Once all non-production deployments are removed, delete the project via:

**Dashboard:**
> Workers & Pages → your project → Settings → Delete project

**API (curl):**
```bash
curl -s -X DELETE \
  "https://api.cloudflare.com/client/v4/accounts/<ACCOUNT_ID>/pages/projects/<PROJECT_NAME>" \
  -H "Authorization: Bearer <CF_API_TOKEN>" | jq '.success'
```

---

## Notes

- The script adds a `0.3s` delay between deletions to avoid Cloudflare API rate limits
- Only `YES` (uppercase) confirms the deletion — any other input aborts safely
- The production (`canonical`) deployment is **always preserved**, even if it appears in the list
- Tokens use the `cfut_` prefix format introduced by Cloudflare for credential scanning safety