# truex-roku-csai-reference-app

This reference application demonstrates how to integrate Infillion's [TrueX](https://infillion.com/media/truex/) and [IDVx](https://infillion.com/media/idvx/) interactive ad experiences into a Roku channel using Client-Side Ad Insertion (CSAI). The implementation showcases a complete end-to-end integration without using Roku Advertising Framework (RAF) for ad playback.

## What are Infillion Interactive Ads?

Infillion offers two types of interactive video advertising products for Full Episode Player (FEP) publishers on Connected TV platforms.

### [TrueX](https://infillion.com/media/truex/) ( Opt-In Engagement Advertising )

**TrueX** presents users with an **interactive choice card** where they choose between engaging with branded content or watching standard video ads. When users opt in and complete the interactive experience, they earn an **ad credit that skips all remaining ads** in the pod, creating a win-win: viewers get ad-free content, and advertisers get highly engaged audiences.

**Key features:**
- **Opt-in via choice card** - Users actively choose to engage
- **Engagement requirements** - Users must spend 30 seconds and interact at least once to earn credit
- **Skips entire ad break** - Successful engagement bypasses all remaining ads in the pod

### [IDVx](https://infillion.com/media/idvx/) ( Interactive Video Advertising )

**IDVx** delivers **interactive video ads that start automatically** without requiring user opt-in. These ads maintain interactivity throughout their duration (typically 30 seconds) and **play inline with other ads** in the break sequence. After an IDVx ad completes, playback continues to the next ad in the pod.

**Key features:**
- **Automatic start** - Begins playing without opt-in
- **Interactive throughout** - Users can interact with ad content during playback
- **Plays inline** - Completes and continues to the next ad in sequence

## VAST Tag Types

Infillion uses two types of VAST tags for both TrueX and IDVx products. The tags differ in how the `adParameters` JSON payload is embedded in the VAST XML.

### "Generic" Tag

The `adParameters` are embedded directly as a JSON string within the `<AdParameters>` node:

**TrueX "Generic" Tag:**
```
https://get.truex.com/{placement_hash}/vast/generic?{ad_request_parameters}
```

**IDVx "Generic" Tag:**
```
https://get.truex.com/{placement_hash}/vast/idvx/generic?{ad_request_parameters}
```

**VAST Structure:**
```xml
<VAST version="4.0">
  <Ad id="...">
    <InLine>
      <AdSystem>trueX</AdSystem> <!-- or "IDVx" for IDVx ads -->
      <Creatives>
        <Creative>
          <Linear>
            <Duration>00:00:30</Duration>
            <AdParameters>
              <![CDATA[
                {
                  "user_id": "...",
                  "placement_hash": "...",
                  "vast_config_url": "..."
                }
              ]]>
            </AdParameters>
            <MediaFiles>
              <MediaFile delivery="progressive" type="video/mp4" width="1280" height="720" apiFramework="truex">
                <![CDATA[https://qa-media.truex.com/m/video/truexloadingplaceholder-30s.mp4 ]]>
              </MediaFile>
            </MediaFiles>
          </Linear>
        </Creative>
      </Creatives>
    </InLine>
  </Ad>
</VAST>
```

### "Companion" Tag

The `adParameters` are embedded in a companion ad's `<StaticResource>` node as base64-encoded json string:

**TrueX "Companion" Tag:**
```
https://get.truex.com/{placement_hash}/vast/companion?{ad_request_parameters}
```

**IDVx "Companion" Tag:**
```
https://get.truex.com/{placement_hash}/vast/idvx/companion?{ad_request_parameters}
```

**VAST Structure:**
```xml
<VAST version="4.0">
  <Ad id="...">
    <InLine>
      <AdSystem>trueX</AdSystem> <!-- or "IDVx" for IDVx ads -->
      <Creatives>
        <Creative>
          <CompanionAds>
            <Companion id="super_tag" width="960" height="540" apiFramework="truex">
              <StaticResource creativeType="application/json">
                <![CDATA[ ...base64_encoded_json_string... ]]>
              </StaticResource>
            </Companion>
          </CompanionAds>
        </Creative>
        <Creative>
          <Linear>
            <Duration>00:00:30</Duration>
            <MediaFiles>
              <MediaFile delivery="progressive" type="video/mp4" width="1280" height="720">
                <![CDATA[https://qa-media.truex.com/m/video/truexloadingplaceholder-30s.mp4 ]]>
              </MediaFile>
            </MediaFiles>
          </Linear>
        </Creative>
      </Creatives>
    </InLine>
  </Ad>
</VAST>
```

### Differentiating TrueX and IDVx

The `<AdSystem>` node value identifies the ad type:
- **TrueX ads**: `<AdSystem>trueX</AdSystem>`
- **IDVx ads**: `<AdSystem>IDVx</AdSystem>`

Both tag types (Generic and Companion) work with both TrueX and IDVx products.

## Implementation Flow

1. **Library Loading**: The app loads `TruexAdRendererLib` during initialization ([main-scene.brs](components/main-scene.brs))
2. **Stream Playback**: Video content plays until reaching an ad break position
3. **Ad Detection**: The app detects TrueX/IDVx ads via the `<AdSystem>` node in VAST
4. **Ad Parameters Extraction**: Decode `adParameters` from either `<AdParameters>` or base64-encoded `<CompanionAd>`
5. **Renderer Initialization**: Create and initialize `TruexAdRenderer` with ad parameters
6. **Event Handling**: Process events to manage ad completion, errors, and user interactions
7. **Resume Playback**: Skip remaining ads (TrueX with `adFreePod`) or continue to next ad (IDVx or TrueX opt-out)

### Loading the SDK

The TrueX Ad Renderer SDK is loaded using Roku's `ComponentLibrary` mechanism. In [main-scene.xml](components/main-scene.xml), declare the library:

```xml
<ComponentLibrary id="TruexAdRendererLib" uri="https://ctv.truex.com/roku/v1/release/TruexAdRenderer-Roku-v1.pkg" />
```

Monitor the library's load status in [main-scene.brs:71-95](components/main-scene.brs#L71-L95):

```brightscript
sub init()
  ' ...
  m.tarLibrary = m.top.findNode("TruexAdRendererLib")
  m.tarLibrary.observeFieldScoped("loadStatus", "onTruexLibraryLoadStatusChanged")
  ' ...
end sub

sub onTruexLibraryLoadStatusChanged(event as Object)
  if m.tarLibrary.loadStatus = "ready" then
    ? "TruexAdRendererLib has been loaded successfully!"
    ' Now safe to initialize the renderer
  end if
end sub
```

The core integration logic is in [playback-screen.brs](components/playback-screen.brs). Key integration points include:

#### Handling `adParameters`

The application needs to handle both "Generic" and "Companion" VAST tag formats to extract the `adParameters`. For "Companion" tags, the Base64-encoded string must be decoded.


```brightscript
  adParametersJsonString = invalid

  if _isNonEmptyString(truexAd.adParameters) then
    adParametersJsonString = truexAd.adParameters
  else if _isArray(truexAd.companionAds) then
    ' this code shows how to handle the ad info result parsed by RAF
    ' in case the app utilizes a custom VAST/VMAP parsing, the code should check the field represents the data
    ' from VAST.Ad.InLine.Creatives.Creative.CompanionAds.Companion[apiFramework="truex"].StaticResource[creativeType="application/json"]

    for each companionAd in truexAd.companionAds
      if LCase(companionAd.provider) = "truex" and _isNonEmptyString(companionAd.url) then
        adParametersBase64String = companionAd.url.Split("data:application/json;base64,")[1]

        if _isNonEmptyString(adParametersBase64String) then
          buffer = CreateObject("roByteArray")
          buffer.FromBase64String(adParametersBase64String.Replace(Chr(10), ""))
          adParametersJsonString = buffer.ToAsciiString()
        end if
        exit for
      end if
    end for
  end if

  if adParametersJsonString = invalid then
    adParameters = {}
  else
    adParameters = ParseJson(adParametersJsonString)
  end if
```

### Initializing TruexAdRenderer

```brightscript
' instantiate TruexAdRenderer
m.tar = m.top.CreateChild("TruexLibrary:TruexAdRenderer")
m.tar.ObserveFieldScoped("event", "onTruexEvent")
m.tar.SetFocus(true)

' initialize the renderer
m.tar.action = {
  type: "init",
  adParameters: adParameters,
  slotType: UCase(adSlotType),       ' "PREROLL" or "MIDROLL"
  ` supportsUserCancelStream: false, ' [optional] set to true to enable the userCancelStream event
  ` logLevel: 5,                     ' [optional] set the logging verbosity, from 0 (mute) to 5 (verbose)
  ` channelWidth: 1920,              ' [optional] set the width in pixels of the channel
  ` channelHeight: 1080              ' [optional] set the height in pixels of the channel
}

' start the ad experience
m.tar.action = { type: "start" }
```

### Handling Ad Events

Process TruexAdRenderer events in [playback-screen.brs:268-321](components/playback-screen.brs#L268-L321):

```brightscript
sub onTruexEvent(msg as Object)
  event = msg.GetData()

  if event.type = "adFreePod" then
    ' User earned ad credit - skip remaining ads (TrueX only)
    m.truexSkipRemainingAds = (LCase(m.currentAd.adSystem) = "truex")
  else if event.type = "adCompleted" then
    ' Ad experience finished - resume content or play next ad
    if m.truexSkipRemainingAds then
      discardCurrentAdPod()  ' Skip to content
    else
      startNextAdInCurrentAdPod()  ' Play next ad
    end if
  else if event.type = "adError" then
    ' Error occurred - continue with standard ads
    startNextAdInCurrentAdPod()
  ' Handle other events...
  end if
end sub
```

The TruexAdRenderer fires events to communicate ad lifecycle and user interactions. For complete documentation, see the [official integration docs](https://github.com/socialvibe/truex-roku-integrations/blob/develop/DOCS.md).

#### Terminal Events

These events end the ad experience:

| Event | Description |
|-------|-------------|
| `adCompleted` | User exits the ad experience. Fires when user opts out, completes interaction, or skip card finishes. |
| `adError` | Unrecoverable error occurred during ad presentation. |
| `noAdsAvailable` | No ads available for the current user. Resume with standard ads. |
| `userCancelStream` | User requested to exit the entire video stream (only if `supportsUserCancelStream` is enabled). |

#### Main Flow Events

These events track the ad experience progression:

| Event | Description |
|-------|-------------|
| `adFetchCompleted` | Ad request completed after `init` action. Useful for managing loading screens. |
| `adStarted` | TrueX UI is ready and displayed after `start` action. |
| `adFreePod` | **TrueX only** User earned ad credit by completing engagement. Skip remaining ads in pod. |
| `adsAvailable` | Ads are ready for presentation. |

#### Informative Events

These events provide tracking information:

| Event | Description |
|-------|-------------|
| `optIn` | User selected to interact with the ad. <br/>**Note**: May fire multiple times if user backs out and opts in again |
| `optOut` | User declined to interact with the ad. |
| `skipCardShown` | Skip card displayed to user in Sponsored Stream flows. |
| `userCancel` | User cancelled during choice card phase. |
| `videoEvent` | Provides video playback tracking information. |

**Important:** The `adFreePod` event is only applicable to the TrueX product and will not fire for IDVx ads, as IDVx ads do not provide ad-skipping functionality.

## Additional Resources

- [Official Integration Documentation](https://github.com/socialvibe/truex-roku-integrations/blob/develop/DOCS.md)
- [TrueX Product Information](https://infillion.com/media/truex/)
- [IDVx Product Information](https://infillion.com/media/idvx/)
