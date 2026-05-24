# DunenBLELogger

Builds `DunenBLELogger.dylib` for BLE logging inside the Dunen app.

## GitHub build
1. Create a new GitHub repo.
2. Upload all files from this zip.
3. Go to **Actions**.
4. Run **Build DunenBLELogger dylib**.
5. Download artifact: `DunenBLELogger-dylib`.

## ESign use
Inject `DunenBLELogger.dylib` into the Dunen IPA.

## Log output
After opening Dunen, the log file should appear inside the Dunen app container:

`Documents/DUNEN_BLE_INJECT_LOG.txt`

Send that TXT file back.

## What it logs
- TX writes to BLE characteristics
- direct read requests
- notify enable
- RX packets from BLE characteristics
