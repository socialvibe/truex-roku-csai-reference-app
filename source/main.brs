' Copyright (c) 2026 TrueX, Inc. All rights reserved.

' Entry point for the reference Channel.
'
' Performs the usual initial setup for a SceneGraph Channel; sets up the Screen with a MessagePort then instantiates
' and presents MainScene, listening on the message port until the Screen is closed.

Library "Roku_Ads.brs"

sub main()
  ? "Ref App >>> main() -- app: ";CreateObject("roAppInfo").GetTitle()

  ' create the host Screen object and attach message port to listen for events
  m.port = CreateObject("roMessagePort")

  ' start rsg
  m.screen = CreateObject("roSGScreen")
  m.screen.SetMessagePort(m.port)
  m.screen.Show()

  ' resolve an app payload: load adpods defs using RAF
  m.payload = resolvePayload()

  ' create and display the main scene
  m.scene = m.screen.CreateScene("MainScene")
  m.scene.CallFunc("setup", m.payload)

  eventLoop()
end sub

function resolvePayload() as Object
  ' load stream info
  payload = ParseJson(ReadAsciiFile("pkg:/res/payload.json").trim())

  ' @see {@link https://developer.roku.com/docs/developer-program/advertising/integrating-roku-advertising-framework.md#ad-structure}
  ' @note RAF knows to parse `<AdSystem/>` and `<AdParameters/>` nodes and makes these available as
  ' - `ad.adSystem`
  ' - `ad.adParameters`
  raf = Roku_Ads()
  raf.SetDebugOutput(false)

  for each example in payload.examples
    if example.ad_url <> invalid then
      raf.SetContentId(example.id)
      raf.SetAdUrl(example.ad_url)

      example.adPods = raf.getAds()

      ' ensure all adpods have .renderTime property - RAF doesn't add it for `preroll` ?!
      for each adPod in example.adPods
        if not(_isNumeric(adPod.renderTime)) then
          adPod.renderTime = 0
        end if
      end for

      ? "Ref App >>> resolvePayload() -- title: '";example.title;"', adPods: ";example.adPods?.Count();", uri: ";example.ad_url
    end if
  end for

  return payload
end function

sub eventLoop()
  ? "Ref App >>> eventLoop() -- started"

  while true
    msg = Wait(0, m.port)
    msgType = Type(msg)
    ? "Ref App >>> eventLoop() -- message received, type=";msgType

    if msgType = "roSGScreenEvent" and msg.IsScreenClosed() then return
  end while

  ? "Ref App >>> eventLoop() -- ended"
end sub
