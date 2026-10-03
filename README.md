# Meme Radar Android

Unofficial community Android port of Meme Radar.

## Features

- Standalone Android scanning
- User-provided AVE API key
- Solana, BSC, Base, Ethereum, Robinhood
- Live Candidates
- Discovery Score
- PRIORITY band
- Candidate sorting
- Background scanning
- Screen-off scanning via Android Foreground Service
- New Candidate notifications
- Local notification dedupe

*Note: Radar Candidate ≠ buy recommendation.*

## Installation

1. Download APK from GitHub Releases
2. Install APK
3. Open Settings
4. Enter your own AVE API Key
5. Test connection
6. Select chain
7. Start Radar

*App does NOT include a shared AVE API key. Each user must provide their own key.*

**API Key Storage:**
- stored locally using Android secure storage
- not intentionally uploaded to developer server
- not included in GitHub source/release APK

## Background Behavior

After clicking "Start Radar":
- first scan runs immediately
- subsequent scans run every 5 minutes
- Android Foreground Service keeps Radar active in background
- persistent Android notification is expected while Radar is running
- new qualified Live Candidates may trigger separate notifications

*Battery Optimization Note:* Different Android OEM battery optimizations may affect long-term background behavior. 
*Android 15+ Note:* This app uses a dataSync Foreground Service. If the app/system combination is affected by Android's runtime limits on dataSync Foreground Services, long-term continuous background scanning may be restricted by the OS.

## Privacy / Data Handling

- scanning happens from the Android device
- AVE API key is supplied by the user
- no developer VPS is required for Radar scanning
- no wallet private key is required
- no trading execution
- no swap
- no automatic orders

Network requests will hit the following third-party APIs used by the project:
- AVE
- DexScreener
- GoPlus

*These third-party services are governed by their respective Terms of Service and Privacy Policies.*

## Beta Disclaimer

**Beta software.**
This is an unofficial community beta. It may contain bugs and should not be treated as financial advice. Meme Radar surfaces market candidates for review; it does not guarantee token safety, profitability, or future performance.

## License

Based on Meme Radar: https://github.com/nhovongoc0-max/meme-radar
Original project/author attribution: nhovongoc0-max
Android port is unofficial/community maintained.
Source is distributed under AGPL-3.0-only.
This project is not an official Android release from the upstream author.
