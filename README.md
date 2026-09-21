# nexinsight (Android)

Nexinsight event tracking SDK for Android. The SDK queues events in a local SQLite database, delivers them to the collector in the background with retries, and survives offline periods and app restarts.

## Installation

The SDK is published to GitHub Packages as `com.nexinsight:sdk`. GitHub Packages requires authentication even for public packages, so you need a GitHub personal access token with the `read:packages` scope.

Put your credentials in `~/.gradle/gradle.properties` (never commit them):

```properties
gpr.user=YOUR_GITHUB_USERNAME
gpr.token=YOUR_GITHUB_TOKEN
```

Add the repository to `settings.gradle.kts`:

```kotlin
dependencyResolutionManagement {
    repositories {
        google()
        mavenCentral()
        maven {
            url = uri("https://maven.pkg.github.com/Nexinsight/android-sdk")
            credentials {
                username = providers.gradleProperty("gpr.user").orNull ?: System.getenv("GITHUB_ACTOR")
                password = providers.gradleProperty("gpr.token").orNull ?: System.getenv("GITHUB_TOKEN")
            }
        }
    }
}
```

Then add the dependency to your module:

```kotlin
// app/build.gradle.kts
dependencies {
    implementation("com.nexinsight:sdk:0.1.0")
}
```

```groovy
// app/build.gradle
dependencies {
    implementation 'com.nexinsight:sdk:0.1.0'
}
```

In CI, `GITHUB_ACTOR` and `GITHUB_TOKEN` are provided automatically by GitHub Actions. The sources jar is published alongside the AAR, so Android Studio shows Javadoc for every class and method.

### Manual installation

If you cannot use GitHub Packages, download `nexinsight.aar` from this repository into `app/libs/` and reference it directly:

```kotlin
dependencies {
    implementation(files("libs/nexinsight.aar"))
}
```

### Requirements

- `minSdk` 21 (Android 5.0) or higher.
- The AAR already declares `android.permission.INTERNET`; you do not need to add it.
- Native libraries are bundled for `arm64-v8a`, `armeabi-v7a`, `x86_64` and `x86`. Use `abiFilters` or app bundles if you want to ship fewer ABIs.
- No external dependencies. SQLite support is compiled into the SDK.

## Usage

### Kotlin

```kotlin
import android.app.Application
import android.os.Build
import com.nexinsight.sdk.eventsdk.Config
import com.nexinsight.sdk.eventsdk.Eventsdk
import com.nexinsight.sdk.eventsdk.Tracker

class App : Application() {
    lateinit var tracker: Tracker

    override fun onCreate() {
        super.onCreate()

        val dbPath = getDatabasePath("nexinsight.db").absolutePath

        val cfg: Config = Eventsdk.newConfig("APP-UUID", dbPath)
        cfg.setDeviceInfo("Android", Build.VERSION.RELEASE, Build.MODEL)
        cfg.setAppInfo("MyApp", BuildConfig.VERSION_NAME, BuildConfig.VERSION_CODE.toString())
        cfg.flushIntervalSeconds = 15

        tracker = Eventsdk.newTracker(cfg)
        tracker.setLogger { level, msg ->
            if (level >= Eventsdk.LogWarn) android.util.Log.w("Nexinsight", msg)
        }
    }
}
```

```kotlin
// In an Activity or Fragment
app.tracker.trackView("home")

// Custom event with parameters
val e = app.tracker.newEvent(Eventsdk.EventView)
e.setScreen("checkout")
e.setCustomParam(1, "promo-42")
app.tracker.track(e)

// Identity sync
app.tracker.identify(otp)
```

Wire the lifecycle callbacks once, for example with `ProcessLifecycleOwner` from `androidx.lifecycle:lifecycle-process`:

```kotlin
ProcessLifecycleOwner.get().lifecycle.addObserver(object : DefaultLifecycleObserver {
    override fun onStart(owner: LifecycleOwner) = tracker.onForeground()
    override fun onStop(owner: LifecycleOwner) = tracker.onBackground()
})
```

On shutdown, `close` performs a final flush and releases the database. Run it off the main thread:

```kotlin
Thread { tracker.close(3000) }.start()
```

### Java

```java
Config cfg = Eventsdk.newConfig("APP-UUID", getDatabasePath("nexinsight.db").getAbsolutePath());
cfg.setDeviceInfo("Android", Build.VERSION.RELEASE, Build.MODEL);
cfg.setAppInfo("MyApp", BuildConfig.VERSION_NAME, String.valueOf(BuildConfig.VERSION_CODE));

Tracker tracker;
try {
    tracker = Eventsdk.newTracker(cfg);
    tracker.trackView("home");
} catch (Exception e) {
    // invalid config or database could not be opened
}
```

Methods that return errors in the underlying implementation are declared `throws Exception` in Java (`newTracker`, `trackView`, `trackClose`, `trackHide`, `trackHideAuto`, `track`, `identify`, `flush`, `close`, `Event.setType`, `Event.setCustomParam`). All other methods do not throw.

## API

All classes live in `com.nexinsight.sdk.eventsdk`.

| Method | Purpose |
|--------|---------|
| `Eventsdk.newConfig(appUUID, dbPath)` | Build a `Config` with defaults applied |
| `Eventsdk.newTracker(cfg)` | Validate config, open the queue, replay pending events, start delivery |
| `trackView(screen)` | Record screen view; becomes current screen and starts the visibility timer |
| `trackClose(screen, seconds)` | Record screen/app closure with visibility duration |
| `trackHide(screen, seconds)` | Record backgrounding with visibility duration |
| `trackHideAuto()` | Hide current screen with computed visibility time |
| `identify(otp)` | Identity sync event carrying a MyGaru OTP |
| `newEvent(type)` + `track(event)` | Custom event with parameters (`cp1`–`cp7`) |
| `setScreen(name)` / `currentScreen()` | Update screen without emitting an event |
| `setUserID(uid)` / `userID()` | Manage user identifier; pass `""` to clear |
| `sessionID()` / `resetSession()` | Retrieve or reset session (e.g. on logout) |
| `installID()` | Stable pseudonymous installation identifier |
| `onForeground()` / `onBackground()` | Lifecycle handlers |
| `flushAsync()` / `flush(timeoutMillis)` | Trigger delivery; blocking variant throws if events remain pending |
| `pendingCount()` / `stats()` | Diagnostics |
| `setLogger(logger)` | Attach a `Logger` for diagnostics; `null` removes it |
| `close(timeoutMillis)` | Final flush and database release |

Only `flush` and `close` block; every other method returns immediately without network or disk I/O on the calling thread. All `Tracker` methods are thread-safe. An `Event` instance is not; build and submit it from a single thread.

### Event

| Method | Purpose |
|--------|---------|
| `setScreen(name)` | Current screen, sent as `cur` |
| `setPrevScreen(name)` | Previous screen, sent as `ref` |
| `setCustomParam(index, value)` | Custom parameter 1–7, sent as `cpN`; empty value removes it |
| `setViewabilityTime(seconds)` | Required for `close` and `hide` events |
| `setUserID(uid)` | Override the tracker-wide user id for this event |
| `setOTP(otp)` | Required for `ident` events |
| `setType(type)` | Override event type; throws on unknown types |

Event type constants: `Eventsdk.EventView`, `EventClose`, `EventHide`, `EventIdent`.

### Stats

`stats()` returns a snapshot with `enqueued`, `persisted`, `delivered`, `dropped`, `retried`, `pending` (`-1` if unknown) and `lastError`.

### Logger

```kotlin
tracker.setLogger { level, msg -> Log.println(toAndroidPriority(level), "Nexinsight", msg) }
```

Levels: `Eventsdk.LogDebug` (0), `LogInfo` (1), `LogWarn` (2), `LogError` (3). Without a logger the SDK is silent.

## Configuration

Initialize with `Eventsdk.newConfig(appUUID, databasePath)` to populate defaults. `databasePath` must reside in private app storage, such as `context.getDatabasePath(...)` or `context.filesDir`. Fields are exposed as Java bean getters and setters (`getEndpoint()` / `setEndpoint(...)`), which Kotlin surfaces as properties.

| Field | Default | Notes |
|-------|---------|-------|
| `endpoint` | `https://a.nexinsight.com.ua/` | Must be an absolute HTTP(S) URL |
| `batchEndpoint` | `endpoint` + `batch` | Override for proxies |
| `userAgent` | Synthesized | Use `WebSettings.getDefaultUserAgent(context)` when available |
| `userAgentSuffix` | From `appName`/`appVersion` | Appended verbatim |
| `osName`, `osVersion`, `deviceModel` | Empty | Set via `setDeviceInfo(...)`; used for UA and platform version |
| `appName`, `appVersion`, `appBuild` | Empty | Set via `setAppInfo(...)` |
| `sessionTimeoutSeconds` | `1800` | Inactivity threshold before a new session |
| `batchSize` | `50` | Events per delivery cycle |
| `maxBatchEvents` | `50` | Events per request (capped at `100`) |
| `useBatchEndpoint` | On | Disable with `disableBatchEndpoint()` |
| `compressBatchThresholdBytes` | `1024` | `0` disables gzip |
| `flushIntervalSeconds` | `15` | Background delivery frequency |
| `ingestBufferSize` | `512` | In-memory hand-off capacity |
| `maxQueueSize` | `10000` | Oldest events dropped beyond the limit |
| `maxAttempts` | `12` | `0` means retry until `maxEventAgeSeconds` |
| `baseBackoffSeconds` / `maxBackoffSeconds` | `2` / `300` | Exponential with ±20% jitter |
| `maxEventAgeSeconds` | `86400` | 24-hour window; `0` disables |
| `requestTimeoutSeconds` | `15` | Per HTTP attempt |
| `maxViewabilityTime` | `1800` | Matches collector limit |
| `sendEventTime` | On | Disable with `disableEventTime()` |
| `debug`, `debugKey`, `devKey` | Off | Collector debug/dev modes |
| `userID`, `sendInstallIDAsUID` | Empty, off | See behavioral notes |
| `autoHideOnBackground` | On | Disable with `disableAutoHideOnBackground()` |

## Behaviour worth knowing

**Sessions.** The session identifier is generated locally and rotates after `sessionTimeoutSeconds` of inactivity, including offline periods. The session persists across app launches within the timeout window. Queued events retain their original session ID regardless of delivery timing.

**Delivery order.** Events are sent in insertion sequence within batches and across delivery cycles, as the collector maintains per-session timestamps to prevent out-of-order distortion.

**Drops.** Events are discarded on permanent rejection (`400` or batch-level rejections), exhausted retry attempts, exceeding `maxEventAgeSeconds`, exceeding `maxQueueSize` (oldest first), or ingest buffer overflow. Each drop increments `stats().dropped` and logs if a logger is attached. Server-side temporary disablement triggers retries rather than drops.

**Event time.** Each event records its device timestamp (`et`), preserving the original time for offline-queued events. The collector accepts timestamps within a 24-hour lookback and 5-minute forward window. Devices with incorrect system clocks eventually have `et` disabled automatically to preserve the event stream. Use `disableEventTime()` to disable from the start.

**Install id.** `installID()` returns a random, persisted pseudonymous identifier. It is not transmitted unless `sendInstallIDAsUID` is enabled, and an explicit `setUserID` takes precedence.

**Process lifetime.** Create one `Tracker` per app process, keep it for the process lifetime, and call `close` on shutdown. Undelivered events stay on disk and are picked up by the next run. After `close` the tracker is unusable and methods fail with `Eventsdk.getErrClosed()`.

**Threads.** `flush` and `close` perform blocking I/O. Do not call them on the main thread.
