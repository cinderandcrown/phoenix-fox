# Meta DAT / Web App skills for Cursor

Pulled from Meta’s FAQ (“Can I use AI coding tools…”) and installed for this project.

| Surface | Upstream | In this workspace |
| --- | --- | --- |
| Device Access Toolkit (iOS) | [meta-wearables-dat-ios](https://github.com/meta/meta-wearables-dat-ios) `install-skills.sh cursor` | `.cursor/rules/meta-dat/*.mdc` |
| Display Web Apps | [meta-wearables-webapp](https://github.com/meta/meta-wearables-webapp) `install-skills.sh cursor` | Cursor plugin `meta-wearables-webapp` (agent machine) |
| Live docs MCP | `https://mcp.developer.meta.com/wearables` | Optional HTTP MCP named `wearables` / `wearables-dat` |

Re-install DAT rules into the repo:

```bash
curl -sL https://raw.githubusercontent.com/meta/meta-wearables-dat-ios/main/install-skills.sh | bash -s cursor
# then copy .cursor/rules into .cursor/rules/meta-dat/ if the installer writes at repo root
```

Prefer these skills over inventing DAT symbol names. Motion, Mock Device Kit, Display, and Speech details change with SDK betas.
