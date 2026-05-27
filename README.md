# wyx2685-v2board Mieru Patch

This repository adds backend Mieru protocol support to `cmz0228/wyx2685-v2board`.

It was derived by comparing `cedar2025/Xboard` Mieru support with the wyx2685 V2Board fork.

## What It Adds

- `v2_server_mieru` database table.
- `ServerMieru` model.
- Admin API:
  - `POST /api/v1/{secure_path}/server/mieru/save`
  - `POST /api/v1/{secure_path}/server/mieru/drop`
  - `POST /api/v1/{secure_path}/server/mieru/update`
  - `POST /api/v1/{secure_path}/server/mieru/copy`
- Node API through UniProxy:
  - `/api/v1/server/uniproxy/config?node_type=mieru&node_id=ID&token=SERVER_TOKEN`
  - `/api/v1/server/uniproxy/user?node_type=mieru&node_id=ID&token=SERVER_TOKEN`
  - `/api/v1/server/uniproxy/push?node_type=mieru&node_id=ID&token=SERVER_TOKEN`
- Clash Meta, Clash Verge, and Clash Nyanpasu subscription output:

```yaml
name: example
type: mieru
server: example.com
port: 443
username: USER_UUID
password: USER_UUID
transport: TCP
```

## Debian 12 Production Install

Run this from the root directory of an existing wyx2685-v2board deployment:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/H2Kimi7/wyx2685-v2board-mieru-patch/main/scripts/install-mieru.sh)
```

Or specify the app directory explicitly:

```bash
APP_DIR=/www/wwwroot/v2board bash <(curl -fsSL https://raw.githubusercontent.com/H2Kimi7/wyx2685-v2board-mieru-patch/main/scripts/install-mieru.sh)
```

The script will:

- Download `patches/wyx2685-mieru-support.patch` from GitHub.
- Back up every touched file under `storage/backups/mieru-patch-*`.
- Apply the code patch with a dry-run check first.
- Create `v2_server_mieru` with `CREATE TABLE IF NOT EXISTS`.
- Clear Laravel config/cache if `artisan` is available.

Set `SKIP_DB=1` to skip database changes:

```bash
SKIP_DB=1 APP_DIR=/www/wwwroot/v2board bash <(curl -fsSL https://raw.githubusercontent.com/H2Kimi7/wyx2685-v2board-mieru-patch/main/scripts/install-mieru.sh)
```

## Important Limitation

This patch does not modify the compiled admin frontend asset `public/assets/admin/umi.js`.

The backend API can create and manage Mieru nodes, but the existing admin UI will not automatically show a dedicated Mieru form unless you rebuild or patch the frontend separately.

## Mieru Node Fields

Required fields for `server/mieru/save`:

- `name`
- `group_id[]`
- `host`
- `port`
- `server_port`
- `rate`
- `transport`: `TCP` or `UDP`

Optional fields:

- `route_id[]`
- `parent_id`
- `tags[]`
- `show`
- `traffic_pattern`

## Files Changed

See [patches/wyx2685-mieru-support.patch](patches/wyx2685-mieru-support.patch).
