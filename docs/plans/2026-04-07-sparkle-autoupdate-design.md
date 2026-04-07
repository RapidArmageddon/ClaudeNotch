# Sparkle Auto-Update Design

## Integration

- Add Sparkle 2 via Swift Package Manager
- SPUStandardUpdaterController handles update UI
- Initialise in AppDelegate on launch

## Appcast

- Host `appcast.xml` in repo root
- URL: `https://raw.githubusercontent.com/RapidArmageddon/ClaudeNotch/main/appcast.xml`
- Each entry: version, download URL, minimum OS, EdDSA signature

## Signing

- EdDSA (Ed25519) keypair generated once with Sparkle's `generate_keys`
- Private key stored locally, never committed
- Public key embedded in Info.plist as `SUPublicEDKey`

## Menu Bar

- Add "Check for Updates..." item using Sparkle's standard action

## Info.plist Additions

- SUFeedURL: appcast URL
- SUPublicEDKey: public key
- SUEnableAutomaticChecks: true
