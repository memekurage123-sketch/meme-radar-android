# Meme Radar Android Architecture

## 1. Current Architecture
- **Framework**: Flutter (Dart)
- **App Structure**: The app is completely standalone. It does NOT depend on a VPS or an external backend. The Android device itself acts as the scanner by running a background task (`FlutterForegroundTask`) that directly polls the API.
- **Data Flow**:
  1. `RadarTaskHandler` (Background Task) runs `_runCycle` every 5 minutes.
  2. `Scanner.cycle()` fetches trending tokens from AVE.
  3. `aveDiscoveryScreen` evaluates each token against hardcoded config rules.
  4. Passing tokens are stored in `_liveDiscoveryRows`.
  5. The task sends `_liveDiscoveryRows` to the main isolate (UI).
  6. UI renders the candidate list.

## 2. Scan Pipeline
- **Frequency**: Every 5 minutes (default `scanIntervalMs` = 300,000, configurable in UI).
- **Target**: Sol, BSC, Base, ETH, Robinhood.
- **Method**: The scanner pulls newly trending tokens using the AVE API's trending endpoint (`/v2/tokens/trending`). It then enriches them by fetching individual pair details (`/v2/pairs/...`).
- **Life of a Token**:
  1. Discovered via AVE's trending API.
  2. Hydrated with detailed pool stats (price, liquidity, volume, transactions).
  3. Evaluated by `aveDiscoveryScreen` rules.
  4. If it passes all rules, it enters `PREQUALIFIED` state and is added to `_liveDiscoveryRows`.
  5. `NotificationService` checks if it's new and shows an Android notification.
  6. The main UI displays it in a `CandidateCard`.

## 3. Data Sources
- **Primary & Only Source**: AVE API (`https://prod.ave-api.com`).
- **Endpoints Used**:
  - Trending: `/v2/tokens/trending`
  - Token Details: `/v2/tokens/{ca}-{chain}`
  - Pair Details: `/v2/pairs/{pair}-{chain}`
  - K-Lines (1m): `/v2/klines/token/{ca}-{chain}`
- **Third-party Dependency**: The app directly uses an AVE API Key configured locally. No GMGN, DexScreener, or GeckoTerminal is currently queried.

## 4. Filtering Conditions
There are strictly defined explicit filtering conditions inside `scoring.dart` and `config.dart`.
Here are the actual conditions applied to screen a token:

- **Market Cap**: Must be between `10000.0` and `150000.0` (Discovery range).
- **Liquidity**: Must be >= `8000.0` (`strictLiquidity`). Tokens below `3000.0` fail outright, but deep screening requires 8K.
- **Pool Age**: Must be >= `300s` (5 minutes) and <= `7 * 86400s` (7 days).
- **Recent Volume**: 5m volume must be > `0`. For mature tokens (>1h old), 5m volume must be at least `100.0` or `liquidity * 0.005`. For old tokens (>6h old), 5m volume must be at least `250.0` or `liquidity * 0.01`.
- **Transactions (5m)**: Must have > `0` buys and > `0` sells.
- **Buy Tax**: Must be <= `0.05` (5%).
- **Sell Tax**: Must be <= `0.05` (5%).
- **Tax Asymmetry**: `|Buy Tax - Sell Tax|` must be <= `0.02`.
- **Dev Holding**: Must be <= `0.01` (1%).
- **Top 10 Concentration**: Must be <= `0.30` (30%).
- **Insider Rate**: Must be <= `0.15` (15%).
- **Bundler Rate**: Must be <= `0.15` (15%).
- **Sniper Hold Rate**: Must be <= `0.08` (8%).
- **Bot Hold Rate**: Must be <= `0.20` (20%).
- **Rug Risk**: Rug ratio must be <= `0.20` (20%).
- **Honeypot / Wash Trading**: Must not be a honeypot, must not have sell limits, must not be wash trading.

## 5. Score Logic
**Score Model Exists: YES**
The score (`discoveryScore`) is calculated directly in `scoring.dart` (`aveDiscoveryScreen`).

- **Base Score**: `35.0` if MC is in Priority Band (`20000.0` - `80000.0`), else `10.0`.
- **Liquidity Factor**: `min(25.0, liquidity / 1000.0)`.
- **Volume Factor**: `min(20.0, volume5m / 1000.0)`.
- **Holder Factor**: `min(20.0, holders / 10.0)`.
- **Maximum Possible Score**: `100.0`.
- **Is it Normalized/Capped?**: Yes, each component is hard-capped (`min(...)`).
- **Trigger**: The score does not determine inclusion (the hard filters do), but it is displayed and used for sorting in the UI (`priority` and `volume5m` sorting options). Priority band tokens trigger 'PRIORITY' badges in notifications.

## 6. Current Android UI Data
**Currently Displayed in Candidate Card:**
- Symbol
- Name
- Chain
- Priority badge
- Token Address (CA)
- Score (`discoveryScore`)
- Market Cap (`mc`)
- Liquidity
- DEV% (`devHolding` - though mapped to `dev` in core, card uses `devHolding`)
- Tax
- Price
- 5m Volume
- 5m Buys
- 5m Sells
- Holders
- Pair Address
- Twitter Handle

## 7. Existing Backend Fields Not Shown in UI
*(Since there's no backend, this refers to fields parsed from AVE but not rendered in CandidateCard)*
- `createdAt` (Token/Pool age timestamp)
- `first_trade_at` / `last_trade_at`
- `volume_u_1h` / `volume_u_24h`
- `price_change_percent5m` (5m price change)
- `buys_24h` / `sells_24h`
- `rug_ratio`, `bundler_rate`, `insider` rate (parsed but only used for filtering)

## 8. Missing Useful Fields
- Social links (Telegram, Website) exist in AVE data but are largely ignored in the UI card.
- 1m/5m price change % is very useful for momentum but not shown.
- Historical charting data (KLINES are supported by AVE client but not currently fetched during scanning cycle or displayed).

## 9. K-line Prerequisites
**READY**
The UI receives `_liveDiscoveryRows` objects, which contain:
- `chain`
- `address` (Token address)
- `pairAddress`
- `createdAt` (Pool/Trade creation timestamp)

All required identifiers are present in the candidate payload.

## 10. Bubble-map Prerequisites
**READY**
The UI receives `_liveDiscoveryRows` objects, which contain:
- `chain`
- `address` (Token address)

All required identifiers are present.

## 11. Best Insertion Points for Future Features
- **K-Line Integration**: In `CandidateCard`'s expanded section. You can use the already implemented `AveClient.tokenKlines(chain, address)` to fetch the 1-minute historical data when the user expands the card or clicks a "Chart" button.
- **Bubble-map Integration**: Similar to K-line, can be added as a separate interactive view or an external link using the `chain` and `address` parameters.

