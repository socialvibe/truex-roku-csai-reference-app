' Copyright (c) 2026 TrueX, Inc. All rights reserved.
'-------------------------------------------------------------------------------------------------------------
' DetailsScreen
'
' Sample TV show-esque details screen. The intent is to simulate common video streaming app (Netflix, etc...)
' user flow. Users can select an 'episode' from a carousel list to start the content stream.
'
' The layout contains: a title text field for the 'TV show', a short description of the 'show', a list of
' 'episodes' to choose from, and a Play button.
'-------------------------------------------------------------------------------------------------------------

sub init()
  ? "Ref App >>> DetailsScreen # init()"

  ' list of example to show
  m.examples = invalid
  ' selected example
  m.example = invalid

  m.rootLayout = m.top.FindNode("baseFlowLayout")

  m.playButton = m.top.FindNode("playButton")
  m.playButton.ObserveField("buttonSelected", "onPlayButtonSelected")

  m.numImagesLoading = 0
  bgPoster = m.top.FindNode("backgroundImage")
  if bgPoster.loadStatus = "loading" then
    bgPoster.ObserveField("loadStatus", "onImageLoaded")
    m.numImagesLoading += 1
  end if
  bgPoster2 = m.top.FindNode("backgroundImage")
  if bgPoster2.loadStatus = "loading" then
    bgPoster2.ObserveField("loadStatus", "onImageLoaded")
    m.numImagesLoading += 1
  end if

  if m.numImagesLoading <= 0 then m.top.visible = true
end sub

sub setup(examples as Object)
  ? "Ref App >>> DetailsScreen # setup() -- examples: ";examples.Count()

  m.examples = examples
  m.example = examples[0]

  m.top.FindNode("detailsFlowTitle").text = _asString(m.example.title)
  m.top.FindNode("detailsFlowDescription").text = _asString(m.example.description)
  m.top.FindNode("episode1").uri = _asString(m.example.cover)
end sub

function onKeyEvent(key as String, press as Boolean) as Boolean
  if not press then return false
  if key = "left" or key = "right" or key = "up" or key = "down" then
    return focusElement(key)
  end if
  return false
end function

' Callback triggered when Play button is selected. Starts the stream by signaling via m.top.event.
sub onPlayButtonSelected()
  ? "Ref App >>> DetailsScreen # onPlayButtonSelected()"
  m.top.event = { trigger: "playButtonSelected", example: m.example }
end sub

' Callback triggered when a Poster's loadStatus gets updated. Toggles the root layout's visibility when all images
' have loaded (or failed to load).
' @param {Object} event
sub onImageLoaded(event as Object)
  data = event.GetData()
  ? "Ref App >>> DetailsScreen # onImageLoaded(loadStatus: ";data;", uri: ";event.GetRoSGNode()?.uri;")"
  if data <> "loading" then m.numImagesLoading -= 1
  if m.numImagesLoading = 0 then m.rootLayout.visible = true
end sub

' Determines the next view element to focus from the given direction.
' @param {String} direction
' @return {Boolean}
function focusElement(direction as String) as Boolean
    playButtonFocus = m.playButton.HasFocus()
    m.rootLayout.SetFocus(true)
    m.playButton.SetFocus(not playButtonFocus)
    return true
end function
