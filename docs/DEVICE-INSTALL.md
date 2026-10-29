# Getting Cabin Dash onto your iPhone (from Windows)

The cloud build in this repository proves **one thing**: whether the code compiles and its tests pass on a simulator. It does not put anything on your phone. This page covers the separate job of installing on a real iPhone.

**Rules this project follows, and asks you to follow:**

* Never put an Apple password, a private key (`.p8`, `.p12`), a certificate (`.cer`) or a provisioning profile (`.mobileprovision`) in the repository. The cloud build refuses to run if it finds one (`scripts/ci/check_repo.py`), and `.gitignore` blocks them.
* Never paste any of those into a chat with Claude either.
* Anything secret goes in **GitHub Settings > Secrets and variables > Actions**, where it is hidden from logs and from people who can see the code.

Everything about Apple's accounts, prices and limits below is from what I know of Apple's published rules and was not re-checked against Apple's website while writing this. Prices and limits change. Confirm on developer.apple.com before paying for anything.

## Why a green simulator build does not mean it will install

A simulator runs on your computer's chip and skips most of what a real phone enforces. A green simulator run does **not** show that:

* the app can be **signed** (a real iPhone refuses to run code that is not signed by an identity Apple trusts);
* the **bundle id** is registered to your account and unique;
* the **provisioning profile** matches the app, your account, and your phone;
* **entitlements** and capabilities are allowed (this app uses none, which is the easy case);
* the build passes Apple's **upload checks** (app icon without transparency, privacy manifest, Info.plist keys). These run only when you archive for distribution;
* **GPS, installed-app detection and the keep-awake setting behave** on a real phone. The simulator fakes the location and has no other apps installed.

The only way to prove those is to build a signed copy and install it. That is what the routes below do.

## How signing and provisioning work (short version)

* A **certificate** says "this build came from this developer". Apple issues it to your account.
* A **provisioning profile** ties together the app's bundle id, the certificate, and either the phones allowed to run it (development) or Apple's distribution system (TestFlight).
* **Automatic signing** lets Xcode ask Apple to create and download both when you build. With an **App Store Connect API key** it can do that on a build machine with nobody logged in. The certificate and profile are created for the build and are never stored in the repository.

## Which route should you take?

| | Cost | Needs a Mac? | How long it lasts | Notes |
|---|---|---|---|---|
| **A. Simulator only** (already set up) | free | no | n/a | Tells you if it compiles. Nothing on the phone. |
| **B. Unsigned build + a Windows sideloading tool, free Apple ID** | free | no | about 7 days, then re-install | Fiddly; relies on third-party tools; you type your Apple ID into the tool on your PC. |
| **C. Paid Apple Developer Program + TestFlight** | about US$99 per year | no | each build lasts 90 days | The reliable route. Install from the TestFlight app. No cable. |
| **D. Borrow a Mac with Xcode, free Apple ID** | free | yes | about 7 days | Works, but you said there is no Mac. |

**Lowest cost on Windows:** B costs nothing. **Lowest hassle:** C. If you want this on your phone for a car that you drive most days, C is the one that will not keep expiring on you.

A rented cloud Mac does not change this. It can build, but it cannot connect to your phone, so it cannot install a development build on it. TestFlight (route C) is the way around that.

### Questions from the brief, answered directly

* **Which Apple account is required?** A free Apple ID is enough for routes B and D. Route C needs the paid Apple Developer Program, enrolled as an individual (an Apple ID with two-factor authentication on).
* **Does a free account work with local Xcode?** Yes. Xcode creates a "Personal Team" and signs the app for your own phone. The app stops opening after about seven days and has to be installed again, there is a small limit on how many apps you can have installed this way (commonly three), and you cannot use TestFlight. It needs a Mac. Cabin Dash needs no special capabilities, so the free limits on capabilities do not matter to it.
* **What secrets does a signed GitHub build need?** For route C: `ASC_KEY_ID`, `ASC_ISSUER_ID` and `ASC_KEY_P8` as secrets, and `APPLE_TEAM_ID`, `CABIN_BUNDLE_ID` and `ENABLE_DEVICE_BUILD` as variables. Details in route C.

---

## Route B: unsigned build + sideloading tool (free)

1. In GitHub: **Actions > Unsigned IPA (manual) > Run workflow**. Run it only after **iOS build** is green.
2. When it finishes, download the `.ipa` from **Code > Releases** (each build is published there, for example as **Cabin Dash Beta 2.2 (build 22)**, and kept), or from the run's artifact named after the version, such as **cabindash-beta-2.2** (a zip with `CabinDash-beta-2.2.ipa` inside; unzip it; artifacts expire after 7 days). Every run is a beta numbered from the run: see "Versions" in the README and `CHANGELOG.md`. Before Beta 2.2 the artifact was called **cabindash-unsigned-ipa**.
3. Install a sideloading tool on your Windows PC. **iLoader worked for this project.** Sideloadly's Apple sign-in failed at the two-factor step for the person who tried it first, and AltStore was not tried, so treat both as possible but unproven here. Follow that tool's own instructions, since they change; I could not check them. They typically need Apple's own iTunes and iCloud for Windows (downloaded from Apple, not the Microsoft Store versions) and your phone plugged in by USB.
4. The tool signs the file using your free Apple ID and installs it.
5. On the iPhone: **Settings > Privacy & Security > Developer Mode** (turn on, restart), and **Settings > General > VPN & Device Management** to trust your Apple ID if the app will not open.
6. About a week later the app stops opening. Repeat from step 3 with the same file (no need to rebuild).

Cautions:

* You type your Apple ID into a third-party program. Consider a separate Apple ID made just for this, with two-factor authentication on. That is my advice, not Apple's.
* The unsigned workflow has run, and the file installed with iLoader on one iPhone. Other tools are untested.
* If you set the `SPOTIFY_CLIENT_ID` variable (see `docs/SPOTIFY-SETUP.md`), the workflow builds it into the app. It is not a secret, but it only reaches builds made after you set it.
* Cabin Dash is built without signing in that workflow, so it can only be as good as the unsigned archive. It adds no entitlements, which is why signing it later on your own machine is plausible.

## Route C: paid membership + TestFlight (signed in the cloud, installs without a cable)

You do all of this in a web browser on Windows.

1. **Enrol** in the Apple Developer Program at developer.apple.com/programs (Apple's price at the time of writing: US$99 per year). Approval can take anywhere from minutes to days.
2. **Find your Team ID:** developer.apple.com > Account > Membership details. It is 10 letters and digits.
3. **Choose your bundle id**, for example `com.yourname.cabindash`. It must be one nobody else has used.
4. **Create the app record:** appstoreconnect.apple.com > Apps > **+** > New App. Platform iOS, pick a name (it must be unique on the App Store; it does not have to match the name shown on the phone), pick the bundle id from step 3. If the id is not offered, register it under developer.apple.com > Account > Certificates, Identifiers & Profiles > Identifiers.
5. **Create an API key:** App Store Connect > Users and Access > Integrations > App Store Connect API > Team Keys > **Generate**. Give it the **Admin** role (I believe automatic signing in the cloud needs it; I could not confirm that, so try App Manager first if you prefer least privilege and move up if the build says it lacks permission). **Download the `.p8` file straight away: Apple lets you download it once.** Write down the **Key ID** and the **Issuer ID** shown on that page.
6. **Add to GitHub:** repository **Settings > Secrets and variables > Actions**.
   * Secrets tab, **New repository secret**: `ASC_KEY_ID`, `ASC_ISSUER_ID`, and `ASC_KEY_P8`. For the last one, open the `.p8` file in Notepad, select everything (including the `-----BEGIN PRIVATE KEY-----` and `-----END PRIVATE KEY-----` lines), copy, and paste as the value.
   * Variables tab, **New repository variable**: `APPLE_TEAM_ID` (step 2), `CABIN_BUNDLE_ID` (step 3), and finally `ENABLE_DEVICE_BUILD` with the value `true`.
7. **Run it:** Actions > **Device build to TestFlight** > Run workflow. Until `ENABLE_DEVICE_BUILD` is `true` this workflow does nothing but print an explanation.
8. In App Store Connect, wait for the build to finish processing (the **TestFlight** tab shows it). Add yourself as an **internal tester** (your own App Store Connect user).
9. On the iPhone, install **TestFlight** from the App Store, sign in with the same Apple ID, accept the invitation, and install Cabin Dash.

Good to know:

* Every build installed this way expires after 90 days. Run the workflow again to get a fresh one.
* Developer Mode is not needed for TestFlight apps.
* If a secret leaks (for example you pasted the `.p8` somewhere), go to App Store Connect > Users and Access > Integrations and **revoke the key**, then create a new one.
* The device workflow is manual-only and never runs on a pull request, so people who can only propose changes cannot trigger it.
* GitHub's "environments" (which can add approval steps to secrets) are not used. As I understand it, GitHub limits them for private repositories on some plans, and I did not want the setup to depend on that.
* **Not verified:** this workflow has never run, and I did not test any of it against Apple's services. The names of options in `ExportOptions.plist` (`app-store-connect`, `destination: upload`) and the permissions the key needs are from memory of Apple's tooling. Expect to fix it using the first error message; the log is saved as an artifact and the failing step is summarized on the run page.

## What each file in this repository does for signing

| File | Role |
|---|---|
| `Config/Signing.xcconfig` | Checked in. Default bundle id, empty Team ID, automatic signing. Contains nothing secret. |
| `Config/Signing.local.xcconfig` | **Not** checked in (git-ignored). Your own Team ID and bundle id, for building on a Mac you own. |
| `project.yml` | Reads the bundle id from the xcconfig. Has no team and no signing style on purpose. |
| `.github/workflows/ios-build.yml` | Simulator build. `CODE_SIGNING_ALLOWED=NO`, no secrets. |
| `.github/workflows/ios-unsigned-ipa.yml` | Manual. Produces the unsigned `.ipa` for route B, numbered as a beta from its run (or a release when **release_version** is filled in). No secrets. |
| `.github/workflows/ios-device-build.yml` | Manual and **off** until `ENABLE_DEVICE_BUILD=true`. Route C. The only workflow that reads secrets. |
