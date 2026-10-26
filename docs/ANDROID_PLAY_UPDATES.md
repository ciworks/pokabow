# Google Play in-app updates

**Status:** Implemented in the Android build; Play delivery still needs device testing.

Pokabow uses the MIT-licensed [InappUpdate 1.1 Godot 4.6 plugin](https://godotengine.org/asset-library/asset/5407) by icecube092. The vendored files are in `addons/inapp_update/` (source repository: `https://github.com/icecube092/GodotInAppUpdate`, commit `a69d3362eb7de86d7266f43dcc9e49d39b183764`). Its Android export plugin includes the Play In-App Update 2.1.0 dependencies. The runtime wrapper is safe when the Android singleton is absent.

When the hub opens, `AppRoot` asks Google Play whether a newer `versionCode` is available. If flexible updates are allowed, the hub offers **Download** or **Later**. Play downloads in the background. After download, the hub offers **Restart now** or **Later**; installation is never prompted during a match. If Play permits only an immediate update, the hub offers **Update now**. The check repeats when the app resumes. A declined offer is deferred until the next app launch. Other platforms skip this feature.

## Release requirements

1. Replace the placeholder `package/unique_name="com.example.pokabow"` in `export_presets.cfg` with the actual Play Console application ID before publishing the first build. Keep it stable afterward.
2. Publish signed builds through Google Play, using the same app ID and signing identity for each release. An APK installed directly from Godot or `adb` does not provide a valid Play in-app update test.
3. Increase `version/code` in the Android export preset for every new Play release. `version/name` and `application/config/version` are display versions; Play uses the integer `versionCode` to decide whether an update exists.
4. Test on a Play-enabled Android device with a tester account. Install release N from an internal testing track, publish N+1 to that track, then launch N and verify the Download prompt, completed download, and Restart now prompt. Internal App Sharing is another supported test path.

The desktop/headless Godot check verifies script loading only. The Play update flow, AAR packaging, dialogs on a phone, and installation require the Play-distributed device test above.
