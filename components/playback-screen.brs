' Copyright (c) 2026 TrueX, Inc. All rights reserved.
'-----------------------------------------------------------------------------------------------------------
' PlaybackScreen
'-----------------------------------------------------------------------------------------------------------

sub init()
  ? "Ref App >>> PlaybackScreen # init()"

  ' store reference to video player
  m.videoPlayer = m.top.findNode("videoPlayer")
  ' tracks whether an `adFreePod` was received from TrueX which should skip the rest of the ads in a pod

  ' input stream info
  m.streamInfo = invalid

  ' @type { preroll: object, midroll: object }
  m.adPods = invalid

  ' current ad variables
  m.currentAdPod = invalid
  m.currentAd = invalid
  m.currentAdIndex = invalid

  ' truex related variables
  ' @see #onTruexEvent
  m.truexUnrecoverableError = false
  m.truexSkipRemainingAds = false

  ' instance of TrueX Ad Renderer
  m.tar = invalid
end sub

sub setup(streamInfo as Object)
  ? "Ref App >>> PlaybackScreen # setup() -- streamInfo: ";streamInfo

  ' save ref
  m.streamInfo = streamInfo
  ' get adpods sorted - i.e adPods.preroll, adPods.midrolls
  m.adPods = sortAdPods(streamInfo)

  if m.adPods.preroll <> invalid then
    startAdPodPlayback(m.adPods.preroll)
  else
    startContentPlayback()
  end if
end sub

sub dispose()
  ? "Ref App >>> PlaybackScreen # dispose()"
end sub

' Currently does not handle any key events.
function onKeyEvent(key as String, press as Boolean) as Boolean
  if not(press) then return false

  ? "Ref App >>> PlaybackScreen # onKeyEvent(key: ";key;", press: ";press.ToStr();")"

  if key = "back" and m.tar = invalid then
    ? "Ref App >>> PlaybackScreen # onKeyEvent() - back pressed while content is playing, requesting stream cancel..."
    ' tearDown()
    ' m.top.event = { trigger: "cancelStream" }
  end if

  return true
end function


'-----------------------------------------------------------------------------------------------------------
' content playback functions
'-----------------------------------------------------------------------------------------------------------


' Starts content video playback from a specified position
'
' This function initializes and starts playback of the main video content.
' It resets ad-related variables, configures the video player, and sets up
' the content for playback.
'
' @param {float} startPosition - The position in seconds from which to start playback (default: 0.0)
sub startContentPlayback(startPosition = 0.0 as Float)
  ? "Ref App >>> PlaybackScreen # startContentPlayback(from: ";startPosition;", url: ";m.streamInfo.url;")"

   ' reset ads variables
  m.currentAdPod = invalid
  m.currentAd = invalid
  m.currentAdIndex = invalid

  ' reset truex renderer vars
  m.truexSkipRemainingAds = false
  m.truexUnrecoverableError = false
  m.tar = invalid

  videoContent = CreateObject("roSGNode", "ContentNode")
  videoContent.url = m.streamInfo.url
  videoContent.title = m.streamInfo.title
  videoContent.streamFormat = "mp4"
  videoContent.playStart = startPosition

  m.videoPlayer.visible = true
  m.videoPlayer.retrievingBar.visible = false
  m.videoPlayer.bufferingBar.visible = false
  m.videoPlayer.retrievingBarVisibilityAuto = false
  m.videoPlayer.bufferingBarVisibilityAuto = false

  m.videoPlayer.EnableCookies()
  m.videoPlayer.SetFocus(true)
  m.videoPlayer.ObserveFieldScoped("position", "onContentVideoPositionChange")
  m.videoPlayer.ObserveFieldScoped("state", "onContentVideoStateChange")

  m.videoPlayer.contentIsPlaylist = false
  m.videoPlayer.content = videoContent
  m.videoPlayer.control = "play"
end sub

sub stopContentPlayback()
  ? "Ref App >>> PlaybackScreen # stopContentPlayback()"

  m.videoPlayer.UnobserveFieldScoped("position")
  m.videoPlayer.UnobserveFieldScoped("state")

  m.videoPlayer.control = "stop"
  m.videoPlayer.visible = false
end sub

' Callback triggered when the video player's playhead changes. Used to keep track of ad pods and
' trigger the instantiation of the TrueX experience.
sub onContentVideoPositionChange()
  ? "Ref App >>> PlaybackScreen # onVideoPositionChange() -- %s, duration: %s".format(Str(m.videoPlayer.position), Str(m.videoPlayer.duration))

  ' check if is it a time to show a midroll
  for each adPod in m.adPods.midrolls
    if m.videoPlayer.position >= adPod.renderTime and not(adPod.viewed) then
      ' stop the content playback and save position
      stopContentPlayback()
      ' start adpod playback
      startAdPodPlayback(adPod)
    end if
  end for
end sub

' Callback triggered when the video player's state changes. Used to transition from the video ad pod back
' to the content stream when the former completes playback.
sub onContentVideoStateChange()
  playbackState = m.videoPlayer.state

  if playbackState = "finished" or playbackState = "error" then
    ' Content stream completed playback, return to the parent scene.
    m.top.event = { trigger: "cancelStream" }
  end if
end sub

'-----------------------------------------------------------------------------------------------------------
' TrueX or IDVx related functions
'-----------------------------------------------------------------------------------------------------------

' Launches the TrueX renderer based on the current ad break as detected by onVideoPositionChange
sub startTruexAd(truexAd as Object, truexAdIndex, adSlotType as String)
  ? "Ref App >>> PlaybackScreen # startTruexAd() -- truexAd: ";truexAd

  ' mark as current
  m.currentAd = truexAd
  m.currentAd.viewed = true
  m.currentAdIndex = truexAdIndex

  ' TrueX utilizes 2 types of tags for Roku
  '
  ' #1 https://get.truex.com/:placement_hash/vast/generic?...
  '    in this case adParameters will be defined as json string in VAST.Ad.InLine.Creatives.Creative.AdParameters
  '
  ' #2 https://get.truex.com/:placement_hash/vast/companion?...
  '    in this case, adParameters will defined as base64 encoded json string in
  '    VAST.Ad.InLine.Creatives.Creative.CompanionAds.Companion[apiFramework="truex"].StaticResource[creativeType="application/json"]
  adParametersJsonString = invalid

  if _isNonEmptyString(truexAd.adParameters) then     ' first, check <AdParameters /> node - tag type #1
    adParametersJsonString = truexAd.adParameters
  else if _isArray(truexAd.companionAds) then         ' second, check companionAd.url - tag type #2
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
    adParameters = {} ' in this case we will let TAR to fail and fire "adError" event
  else
    adParameters = ParseJson(adParametersJsonString)
  end if

  ? "Ref App >>> PlaybackScreen # startTruexAd() -- adParameters: ";adParameters

  ' get the app design resolution
  screen = m.top.GetScene().currentDesignResolution

  ' instantiate TruexAdRenderer and register for event updates
  m.tar = m.top.createChild("TruexLibrary:TruexAdRenderer")
  m.tar.id = "tar-%s-%s".format(adSlotType, _asString(truexAd.creativeId))
  m.tar.focusable = true
  m.tar.ObserveFieldScoped("event", "onTruexEvent")
  m.tar.SetFocus(true)

  ' reset flag
  m.truexUnrecoverableError = false

  ' init the renderer
  m.tar.action = {
    type: "init",
    adParameters: adParameters,
    slotType: UCase(adSlotType),
    supportsUserCancelStream: true, ' enables cancelStream event types, disable if Channel does not support
    logLevel: 5,                    ' [optional] set the verbosity of TrueX logging, from 0 (mute) to 5 (verbose), defaults to 5
    channelWidth: screen.width,     ' [optional] set the width in pixels of the channel's interface, defaults to 1920
    channelHeight: screen.height    ' [optional] set the height in pixels of the channel's interface, defaults to 1080
  }

  ' start only there were no errors during init
  ' @see onTruexEvent - "adError" event handling
  if not(m.truexUnrecoverableError) then
    m.tar.action = { type: "start" }
  end if
end sub

sub disposeTruexAdInstance()
  if m.tar = invalid then
    ? "Ref App >>> disposeTruexAdInstance() -- no instance, skipping"
    return
  end if

  ? "Ref App >>> disposeTruexAdInstance()"

  m.truexUnrecoverableError = false
  m.truexSkipRemainingAds = false

  m.tar.UnobserveFieldScoped("event")
  m.tar.SetFocus(false)

  m.top.RemoveChild(m.tar)

  m.tar = invalid
end sub

' Callback triggered when TruexAdRenderer updates its 'event' field.
' Full documentation for the below events can be found here: {@link https://github.com/socialvibe/truex-roku-integrations/blob/develop/DOCS.md}
'
' The following event types are supported:
'   * adFreePod - user has met engagement requirements, skips past remaining pod ads
'   * adStarted - user has started their ad engagement
'   * adFetchCompleted - TruexAdRenderer received ad fetch response
'   * optOut - user has opted out of TrueX engagement, show standard ads
'   * optIn - this event is triggered when a user decides opt-in to the TrueX interactive ad
'   * adCompleted - user has finished the TrueX engagement, resume the video stream
'   * adError - TruexAdRenderer encountered an error presenting the ad, resume with standard ads
'   * adsAvailable - TruexAdRenderer has an ad ready to present
'   * noAdsAvailable - TruexAdRenderer has no ads ready to present, resume with standard ads
'   * userCancel - This event will fire when a user backs out of the TrueX interactive ad unit after having opted in.
'   * userCancelStream - user has requested the video stream be stopped
sub onTruexEvent(msg as Object)
  event = msg.GetData()

  ? "Ref App >>> PlaybackScreen # onTruexEvent() -- ";FormatJson(event)

  if event.type = "adFreePod" then
    ' this event is triggered when a user has completed all the TrueX engagement criteria
    ' this entails interacting with the TrueX ad and viewing it for X seconds (usually 30s)
    ' user has earned credit for the engagement, ensure video ads are skipped when stream is resumed
    m.truexSkipRemainingAds = (LCase(m.currentAd.adSystem) = "truex")
  else if event.type = "adStarted" then
    ' this event is triggered when the TrueX Choice Card is presented to the user
  else if event.type = "adFetchCompleted" then
    ' this event is triggered when TruexAdRenderer receives a response to an ad fetch request
  else if event.type = "optOut" then
    ' this event is triggered when a user decides not to view a TrueX interactive ad
    ' that means the user was presented with a Choice Card and opted to watch standard video ads
    ' we should resume the stream from the video ads
  else if event.type = "optIn" then
    ' this event is triggered when a user decides opt-in to the TrueX interactive ad
  else if event.type = "adCompleted" then
    ' this event is triggered when TruexAdRenderer is done presenting the ad
    ' if the user earned credit (via "adFreePod") their content will be seeked past the ad break
    ' if the user has not earned credit they will resume at the beginning of the ad break
    if m.truexSkipRemainingAds then
      discardCurrentAdPod()
    else
      startNextAdInCurrentAdPod()
    end if
  else if event.type = "adError" then
    m.truexUnrecoverableError = true
    ' this event is triggered whenever TruexAdRenderer encounters an error
    ' usually this means the video stream should continue with normal video ads
    startNextAdInCurrentAdPod()
  else if event.type = "adsAvailable" then
    ' this event is triggered when TruexAdRenderer receives an usable TrueX ad in the ad fetch response
  else if event.type = "noAdsAvailable" then
    ' this event is triggered when TruexAdRenderer receives no usable TrueX ad in the ad fetch response
    ' usually this means the video stream should continue with normal video ads
    startNextAdInCurrentAdPod()
  else if event.type = "userCancel" then
    ' This event will fire when a user backs out of the TrueX interactive ad unit after having opted in.
    ' The flow goes back to the Choice Card opt-in flow within the TrueX experience.
  else if event.type = "userCancelStream" then
    ' this event is triggered when the user performs an action interpreted as a request to end the video playback
    ' this event can be disabled by adding supportsUserCancelStream=false to the TruexAdRenderer init payload
    ' there are two circumstances where this occurs:
    '   1. The user was presented with a Choice Card and presses Back
    '   2. The user has earned an adFreePod and presses Back to exit engagement instead of Watch Your Show button
    ? "Ref App >>> PlaybackScreen # onTruexEvent() - user requested video stream playback cancel..."
    ' tearDown()
    ' m.top.event = { trigger: "cancelStream" }
  end if
end sub

'-----------------------------------------------------------------------------------------------------------
' adpod playback functions
'-----------------------------------------------------------------------------------------------------------


' Starts playback of an ad pod containing multiple ads
'
' This function initializes ad pod playback by setting the current ad pod,
' marking it as viewed, and resetting all ad-related state variables.
' It then begins playback of the first ad in the pod.
'
' @param {Object} adPod - The ad pod object containing:
'   - renderSequence: sequence identifier for the ad pod
'   - ads: array of ad objects to be played
'   - viewed: boolean flag indicating if the pod has been viewed
sub startAdPodPlayback(adPod as Object)
  ? "Ref App >>> PlaybackScreen # startAdPodPlayback() -- adPod: ";adPod.renderSequence;", ads: ";adPod.ads.Count()

  ' save as current
  m.currentAdPod = adPod
  m.currentAdPod.viewed = true

  ' reset
  m.currentAd = invalid
  m.currentAdIndex = invalid

  ' reset truex skip ad pod flag
  m.truexSkipRemainingAds = false

  startNextAdInCurrentAdPod()
end sub

' Starts the next ad in the current ad pod sequence
'
' This function handles the transition between ads within an ad pod by:
' - Disposing of the current TrueX/IDVX ad instance if applicable
' - Calculating the next ad index in the sequence
' - Checking if the ad pod is complete and resuming content playback if so
' - Starting the appropriate ad type (TrueX/IDVX or regular video ad) based on the ad system
sub startNextAdInCurrentAdPod()
  ' dispose current ad
  if m.currentAd <> invalid then
    if (LCase(m.currentAd.adSystem) = "truex" or LCase(m.currentAd.adSystem) = "idvx") then
      disposeTruexAdInstance()
    else
      disposeVideoAd()
    end if
  end if

  ' gen next ad index
  if not(_isInteger(m.currentAdIndex)) then
    nextAdIndex = 0
  else
    nextAdIndex = m.currentAdIndex + 1
  end if

  ' check if the current ad pod completed
  if nextAdIndex >= m.currentAdPod.ads.Count() then
    ? "Ref App >>> PlaybackScreen # startNextAdInCurrentAdPod() -- adpod completed, resuming the content playback"
    startContentPlayback(m.currentAdPod.renderTime + .5)
    return
  end if

  ' get next ad info
  nextAd = m.currentAdPod.ads[nextAdIndex]

  ? "Ref App >>> PlaybackScreen # startNextAdInCurrentAdPod() -- next: ";nextAdIndex;", ad: ";nextAd

  ' start next, check if the next is truex or idvx
  if (nextAdIndex = 0 and LCase(nextAd.adSystem) = "truex") or LCase(nextAd.adSystem) = "idvx" then
    startTruexAd(nextAd, nextAdIndex, m.currentAdPod.renderSequence)
  else
    startVideoAd(nextAd, nextAdIndex)
  end if
end sub

sub discardCurrentAdPod()
  if m.currentAdPod = invalid then
    ? "Ref App >>> PlaybackScreen # discardCurrentAdPod() -- ignoring, executed not during adpod playback"
    return
  end if

  resumeTime = m.currentAdPod.renderTime + .5

  ? "Ref App >>> PlaybackScreen # discardCurrentAdPod() -- resuming content playback from: ";resumeTime

  ' reset ad pod and related variables
  m.currentAdPod = invalid
  m.currentAd = invalid
  m.currentAdIndex = invalid

  m.truexSkipRemainingAds = false
  m.truexUnrecoverableError = false

  startContentPlayback(resumeTime)
end sub

sub startVideoAd(videoAd as Object, videoAdIndex as Integer)
  ? "Ref App >>> PlaybackScreen # startVideoAd() -- index: ";videoAdIndex;", ad: ";videoAd

  ' mark as current
  m.currentAd = videoAd
  m.currentAd.viewed = true
  m.currentAdIndex = videoAdIndex

  videoAdContentNode = CreateObject("roSGNode", "ContentNode")
  videoAdContentNode.url = videoAd.streams[0].url
  videoAdContentNode.title = m.streamInfo.title
  videoAdContentNode.streamFormat = "mp4"
  videoAdContentNode.playStart = 0

  m.videoPlayer.ObserveFieldScoped("position", "onVideoAdPositionChange")
  m.videoPlayer.ObserveFieldScoped("state", "onVideoAdStateChange")

  m.videoPlayer.contentIsPlaylist = false
  m.videoPlayer.visible = true
  m.videoPlayer.content = videoAdContentNode
  m.videoPlayer.control = "play"

  m.videoPlayer.SetFocus(true)
end sub

sub disposeVideoAd()
  ? "Ref App >>> PlaybackScreen # disposeVideoAd()"

  ' remove listeners
  m.videoPlayer.UnobserveFieldScoped("position")
  m.videoPlayer.UnobserveFieldScoped("state")

  ' stop if not stopped yet
  m.videoPlayer.visible = false
  m.videoPlayer.control = "stop"
end sub

sub onVideoAdPositionChange()
  ? "Ref App >>> PlaybackScreen # onVideoAdPositionChange() -- %s, duration: %s".format(Str(m.videoPlayer.position), Str(m.videoPlayer.duration))
end sub

sub onVideoAdStateChange()
  ? "Ref App >>> PlaybackScreen # onVideoStateChange() -- state: %s".format(m.videoPlayer.state)

  if m.videoPlayer.state = "finished" then
    startNextAdInCurrentAdPod()
  else if m.videoPlayer.state = "error" then
    ? "Ref App >>> PlaybackScreen # onVideoAdStateChange() -- error: ";m.videoPlayer.errorStr
    startNextAdInCurrentAdPod()
  end if
end sub

' Sorts ad pods from stream information into preroll and midroll categories
'
' This function processes an array of ad pods from the stream info object and
' categorizes them based on their render sequence. Preroll ads are stored as
' a single object, while midroll ads are collected in an array.
'
' @param {Object} streamInfo - The stream information object containing .adPods array
' @return {Object} - An object with two properties:
'   - preroll: The preroll ad pod object or invalid if none found
'   - midrolls: An array of midroll ad pod objects
function sortAdPods(streamInfo as Object) as Object
  result = {
    preroll: invalid,
    midrolls: [],
  }

  if _isArray(m.streamInfo?.adPods) then
    for each adPod in m.streamInfo.adPods
      if adPod.renderSequence = "preroll" then
        result.preroll = adPod
      else
        result.midrolls.Push(adPod)
      end if
    end for
  end if

  return result
end function
