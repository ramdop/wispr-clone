# Deploying Wispr Clone to Other Macs

You DO NOT need to run the build script or use Xcode on your other devices. You just need to transfer the compiled app.

## The "Elegant" Way (Zip Transfer)

We have created a release script that builds a portable `.zip` file.

### 1. Build the Release (On this Mac)

Run the release script once to generate the package:

```bash
cd "Desktop/Build Things/wispr clone/WisprClone"
chmod +x scripts/release.sh
./scripts/release.sh
```

This will create a new folder called **`Release`** containing `WisprClone_Release.zip`.

> **⚠️ IMPORTANT**: After making code changes, always run `./scripts/build_app.sh` first to create the `.app` bundle. Running `xcodebuild` alone only produces an executable in DerivedData, not the distributable app bundle.

### 2. Transfer

Send `WisprClone_Release.zip` to your other Mac via:

- **AirDrop** (Fastest)
- **iCloud Drive**
- **USB Drive**

### 3. Install (On the Target Mac)

1. **Unzip** the file.
2. **Drag & Drop** `WisprClone.app` into your **Applications** folder.
3. **First Launch (Gatekeeper Bypass)**:
   - Since we don't have a paid Apple Developer ID ($99/yr), macOS will warn that the developer is unidentified.
   - **Right-Click** (or Control-Click) the app icon.
   - Select **Open**.
   - Click **Open** in the dialog box.

   _(You only need to do this once. Future launches will be normal.)_

### Troubleshooting "Damaged" Message

If macOS says _"WisprClone is damaged and can't be opened"_, it's a security quarantine issue, not actual damage.

**Fix:**
Open Terminal on the target Mac and run:

```bash
xattr -cr /Applications/WisprClone.app
```

Then launch it again.

---

## Upgrade Process

When you make changes (like the recent Groq speedup) and want to update your other Macs:

1. Run `./scripts/release.sh` again here.

## "Why isn't this like a regular app?" (The \$99 Apple Tax)

To allow users to just "Download & Open" without warnings, Apple requires **Notarization**. This certifies the app is free of malware.

**To do this, you must:**

1.  Enroll in the [Apple Developer Program](https://developer.apple.com/programs/) ($99/year).
2.  Get a **Developer ID Application** certificate.
3.  Sign the app with that certificate (instead of "Ad-Hoc").
4.  Submit the app to Apple for Notarization using `xcrun notarytool`.

**If you have a Developer Account, here is the command:**

```bash
xcrun notarytool submit WisprClone.zip --keychain-profile "AC_PASSWORD" --wait
```

Once notarized, the app will open immediately on any Mac, just like Chrome or Spotify. Until then, the "Right-Click > Open" bypass is the free standard.
