# EchoCity Android Build

The Android application uses Capacitor to package the existing EchoCity web client without changing the website workflow.

## Requirements

- Node.js 20 or newer
- Android Studio with Android SDK installed
- Java 17

## First setup

```bash
npm install
npm run android:sync
npx cap open android
```

## Build in Android Studio

1. Wait for Gradle synchronization to finish.
2. For a test APK, choose **Build > Build Bundle(s) / APK(s) > Build APK(s)**.
3. For Huawei AppGallery or Xiaomi GetApps, choose **Build > Generate Signed Bundle / APK** and create a signed AAB or APK.

## Update after website changes

```bash
npm run android:sync
```

Then rebuild the signed application in Android Studio.

## Download the automatic test APK

Every push to `main` that changes the app starts the **Build EchoCity Android APK** GitHub Actions workflow. Open the completed workflow run and download the `EchoCity-Android-Debug-APK` artifact. This debug APK is for testing on Android phones; app-store publishing still requires a private signing key and a release build.
