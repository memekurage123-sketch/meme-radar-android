# Upstream Mapping & Synchronization Record

- **Upstream Repository**: `https://github.com/nhovongoc0-max/meme-radar`
- **Synced Tag / Release**: `v0.1.12`
- **Synced Commit**: `7ecd342b2ddbdd72bb4ad3a0d190968a8930467c` (`7ecd342`)
- **License**: AGPL-3.0-only
- **Original Author**: DeFi狙击手 (@bi_9527zx)

---

## File Mapping Table

| Upstream JS File (`src/`) | Dart Port (`lib/radar_core/`) | Category | Description | Status |
| :--- | :--- | :--- | :--- | :--- |
| `src/address.mjs` | `lib/radar_core/address.dart` | Core | Token/Pool address normalization & validation | Completed & Verified |
| `src/pool-identity.mjs` | `lib/radar_core/pool_identity.dart` | Core | Pool address verification and identity matching | Completed & Verified |
| `src/chart-risk.mjs` | `lib/radar_core/chart_risk.dart` | Core | K-line risk exclusion and pattern heuristics | Completed & Verified |
| `src/scoring.mjs` | `lib/radar_core/scoring.dart` | Core | Discovery screen, deep screen, scoring & weights | Completed & Verified |
| `src/social.mjs` | `lib/radar_core/social.dart` | Core | Social community verification & fallback gate | Completed & Verified |
| `src/outcomes.mjs` | `lib/radar_core/outcomes.dart` | Core | Outcome tracking and historical sample collection | Completed & Verified |
| `src/live-leads.mjs` | `lib/radar_core/live_leads.dart` | Core | Fast lead tracking, pruning and reconciliation | Completed & Verified |
| `src/live-discovery.mjs` | `lib/radar_core/live_discovery.dart` | Core | Real-time token discovery engine | Completed & Verified |
| `src/secondary.mjs` | `lib/radar_core/secondary.dart` | Core | DexScreener & GoPlus secondary verification | Completed & Verified |
| `src/ave.mjs` | `lib/radar_core/ave.dart` | Core | AVE API client, CU budget, shared rate-limit lane | Completed & Verified |
| `src/scanner.mjs` | `lib/radar_core/scanner.dart` | Core | Main scan loop, candidate pipeline & state machine | Completed & Verified |
| `src/config.mjs` | `lib/radar_core/config.dart` | Config | Default constants, chain settings & thresholds | Completed & Verified |
| `src/state.mjs` | `lib/radar_core/state.dart` | State | In-memory candidate list & active leads state | Completed & Verified |

---

## Files Intentionally Omitted from Radar Core (Desktop / Node Server Specific)

| Upstream File | Reason for Omission in Native Mobile Client |
| :--- | :--- |
| `src/server.mjs` | Node.js `node:http` local API server. Replaced by native Dart/Flutter models & state. |
| `src/updater.mjs` | Desktop Git/tarball self-updater. Android uses in-app APK version check / GitHub Releases. |
| `src/windows-proxy.mjs` | Windows registry proxy detection. Mobile uses Android OS-level proxy settings. |
| `public/*` | Web UI. Replaced by native Flutter UI in Phase 2. |

---

## Testing & Parity Status

**JS ↔ Dart automated parity:**
- 26/26 PASS
- 100% matched business logic semantics, scoring, filtering rules, and reasons across core components.

**Status as of Unofficial Android Port v0.1.0-beta.1**
This Android port is unofficial and community maintained. It is not an official Android release from the upstream author.
