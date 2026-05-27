# bb-api - Bitbucket Cloud API CLI

Shell wrapper for Bitbucket Cloud REST API 2.0.

## Setup

### 1. Create Bitbucket API Token

Go to: https://bitbucket.org/account/settings/api-tokens/

Required scopes:
- `read:repository:bitbucket`
- `read:pullrequest:bitbucket`
- `write:pullrequest:bitbucket`

### 2. Store in macOS Keychain

```bash
security add-generic-password \
  -a "your-email@example.com" \
  -s "bitbucket-api-token" \
  -w "YOUR_TOKEN_HERE" \
  -U
```

### 3. Configure

Set environment variables (all required):

```bash
# Add to ~/.zshrc or ~/.bashrc, or use .env file next to the script
export BB_API_EMAIL="your-email@example.com"
export BB_API_WORKSPACE="your-workspace"
export BB_API_REPO="your-repo"
```

### Dependencies

- `curl` - HTTP client
- `jq` - JSON processor
- macOS `security` - Keychain access

## Usage

```bash
# List open PRs
bb-api pr list

# Create PR from current branch (target, title, optional description)
bb-api pr create main "Fix login redirect" "Resolves redirect loop on expired session"

# PR details with changed files
bb-api pr show 18

# Full diff
bb-api pr diff 18

# List comments (shows inline location if present)
bb-api pr comments 18

# Add general comment
bb-api pr comment 18 "Looks good overall"

# Inline comment on specific file:line (new code)
bb-api pr inline 18 "src/auth.ts" 42 "Consider extracting to a helper"

# Inline comment on deleted line (old code)
bb-api pr inline-old 18 "src/auth.ts" 10 "This was important, why removed?"

# Approve PR
bb-api pr approve 18

# Reply to a comment (in thread)
bb-api pr reply 18 753926626 "Good point, fixed"

# Edit a comment
bb-api pr edit-comment 18 753926626 "Updated text"

# Delete a comment
bb-api pr delete-comment 18 753926626

# Raw API calls
bb-api raw "/pullrequests"
bb-api raw-post "/pullrequests/18/comments" '{"content":{"raw":"test"}}'
```

## Inline Comments

Two types depending on which side of the diff you're commenting on:

| Command | `inline` field | Use case |
|---------|---------------|----------|
| `pr inline` | `"to": <line>` | Comment on new/modified code |
| `pr inline-old` | `"from": <line>` | Comment on deleted/old code |

Line numbers correspond to the actual file line numbers, not diff line numbers.

## Authentication

- Uses **Basic Auth** with `email:api-token` (Bitbucket requirement since Sept 2025)
- Token stored in macOS Keychain (not plaintext)
- Old App Passwords deprecated, will be disabled June 2026

## API Reference

- Base URL: `https://api.bitbucket.org/2.0/repositories/{workspace}/{repo}`
- [Bitbucket REST API docs](https://developer.atlassian.com/cloud/bitbucket/rest/)
- [Pull Requests API](https://developer.atlassian.com/cloud/bitbucket/rest/api-group-pullrequests/)

## Limitations

- **No pending/draft comments** - all comments are published immediately via API. Bitbucket's "Start review" batching only works in the web UI.
