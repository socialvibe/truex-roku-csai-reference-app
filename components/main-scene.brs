' Copyright (c) 2026 TrueX, Inc. All rights reserved.
'----------------------------------------------------------------------------------------------
' MainScene
'----------------------------------------------------------------------------------------------
' Drives UX by coordinating Screen's.
' Begins TrueX ComponentLibrary loading process, ensures global fields are initialized, and presents
' the LoadingScreen to indicate that a (potentially) long running operation is being performed.
'------------------------------------------------------------------------------------------------------
sub init()
  ? "Ref App >>> MainScene # init()"

  ' grab a reference to the root layout node, which will be the parent layout for all nodes
  m.rootLayout = m.top.findNode("rootLayout")

  ' @see {@link res/payload.json }
  m.payload = invalid

  ' @see #showScreen
  m.currentScreen = invalid

  ' listen for Truex library load events
  m.tarLibrary = m.top.findNode("TruexAdRendererLib")
  m.tarLibrary.observeFieldScoped("loadStatus", "onTruexLibraryLoadStatusChanged")

  ' create/set global fields with Channel dimensions (m.global.channelWidth/channelHeight)
  setChannelWidthHeightFromRootScene()

  ' initially present loading screen while Truex library is downloaded and compiled
  showScreen("LoadingScreen")
end sub

' ---------------------------------------------------------------------
sub setup(payload as Object)
  ? "Ref App >>> MainScene # setup() -- payload: ";FormatJson(payload)

  ' save
  m.payload = payload
  ' present the DetailsScreen now that the Truex library is ready
  showDetailsScreenIfReady()
end sub

'-------------------------------------------------------------------
' Callback triggered by Screen's when their m.top.event field is set.
'
' Supported triggers:
'   * playButtonSelected - transition to ContentScreen
'   * cancelStream - transition to DetailsScreen
'
' Params:
'   * msg as roSGNodeEvent - contains the Screen event data
'-------------------------------------------------------------------
sub onScreenEvent(msg as Object)
  event = msg.GetData()
  ? "Ref App >>> MainScene # onScreenEvent(trigger: ";event.trigger;")"

  if event.trigger = "playButtonSelected" then
    showScreen("PlaybackScreen", event.example)
  else if event.trigger = "cancelStream" then
    showScreen("DetailsScreen", m.payload.examples)
  end if
end sub

'---------------------------------------------------------------------------------
' Callback triggered when the TrueX ComponentLibrary's loadStatus field is set.
'
' Replaces LoadingScreen with DetailsScreen upon success.
'
' Params:
'   * event as roSGNodeEvent - use event.GetData() to get the loadStatus
'---------------------------------------------------------------------------------
sub onTruexLibraryLoadStatusChanged(event as Object)
  ' make sure tarLibrary has been initialized
  if m.tarLibrary = invalid then
    return
  end if

  log = "Ref App >>> MainScene # onTruexLibraryLoadStatusChanged(loadStatus=%s)".format(m.tarLibrary.loadStatus.toStr())

  ' check the library's loadStatus
  if m.tarLibrary.loadStatus = "none" then
    ? log;" -- TruexAdRendererLib is not currently being downloaded"
  else if m.tarLibrary.loadStatus = "loading" then
    ? log;" -- TruexAdRendererLib is currently being downloaded and compiled"
  else if m.tarLibrary.loadStatus = "ready" then
    ? log;" -- TruexAdRendererLib has been loaded successfully!"

    ' present the DetailsScreen now that the Truex library is ready
    showDetailsScreenIfReady()
  else if m.tarLibrary.loadStatus = "failed" then
    ? log;" -- TruexAdRendererLib failed to load"

    ' present the DetailsScreen, streams should use standard ads since the Truex library couldn't be loaded
    showDetailsScreenIfReady()
  end if
end sub

'----------------------------------------------------------------------------------
' Instantiates and presents a new Screen component of the given name.
'
' The current Screen is not removed until the new Screen is successfully instantiated.
'
' Params:
'   * screenName as String - required; the component name of the new Screen
'----------------------------------------------------------------------------------
sub showScreen(screenName as String, data = invalid as Dynamic)
  ' make sure the requested Screen can be instantiated before removing current Screen
  screen = CreateObject("roSGNode", screenName)

  if screen = invalid then
    ? "Ref App >>> MainScene # showScreen(screenName: ";screenName;") - failed to create a screen instance"
    return
  end if

  ? "Ref App >>> MainScene # showScreen(screenName: ";screenName;")"

  ' remove current screen
  removeCurrentScreen()

  ' add the new Screen to the layout
  m.top.AppendChild(screen)

  ' update currentScreen reference and give it focus
  m.currentScreen = screen
  m.currentScreen.SetFocus(true)
  m.currentScreen.ObserveFieldScoped("event", "onScreenEvent")
  m.currentScreen.CallFunc("setup", data)
end sub

sub showDetailsScreenIfReady()
  if m.payload?.examples <> invalid and m.tarLibrary?.loadStatus = "ready" then
    ? "Ref App >>> MainScene # showDetailsScreenIfReady()"
    showScreen("DetailsScreen", m.payload.examples)
  else
    ? "Ref App >>> MainScene # showDetailsScreenIfReady() -- not ready yet"
  end if
end sub

'-----------------------------------------------------------------------
' Clears m.currentScreen's event listener and removes it from the layout.
'
' Does nothing if m.currentScreen is not set.
'-----------------------------------------------------------------------
sub removeCurrentScreen()
  ? "Ref App >>> MainScene # removeCurrentScreen(currentScreen: ";m.currentScreen?.subtype?();")"

  if m.currentScreen = invalid then
    return
  end if

  ' remove from the scene
  m.top.RemoveChild(m.currentScreen)

  ' remove listeners and dispose
  m.currentScreen.UnobserveFieldScoped("event")
  m.currentScreen.CallFunc("dispose", invalid)

  m.currentScreen = invalid
end sub
