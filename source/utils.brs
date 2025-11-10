' Copyright (c) 2026 TrueX, Inc. All rights reserved.
'-----------------------------------------------------
' Some helper functions for updating m.global fields.
'-----------------------------------------------------

' Queries m.top.GetScene().currentDesignResolution to determine the dimensions of the currently running Channel,
' defaulting to 1920x1080 if unavailable. The width and height are then stored in m.global.channelWidth
' and m.global.channelHeight, respectively.
sub setChannelWidthHeightFromRootScene()
  ? "Ref App >>> Utils::setChannelWidthHeightFromRootScene()"

  ' default to 1920x1080 resolution (fhd)
  channelWidth = 1920
  channelHeight = 1080

  ' overwrite defaults using Scene.currentDesignResolution values, if available
  if m.top.getScene() <> invalid then
    designResolution = m.top.getScene().currentDesignResolution
  end if

  if designResolution <> invalid then
    channelWidth = designResolution.width
    channelHeight = designResolution.height
    ? "Ref App >>> Utils::setChannelWidthHeightFromRootScene() - setting from Scene's design resolution: ";channelWidth;"x";channelHeight
  end if

  ' safely set the m.global channelWidth and channelHeight fields
  setGlobalField("channelWidth", channelWidth)
  setGlobalField("channelHeight", channelHeight)
end sub

' Safely sets the value of a field in m.global, adding it explicitly (via addFields) if it doesn't exist.
'
'@param {String} fieldName - name of the field that will take the fieldValue
'@param {Dynamic} fieldValue - value of the global field, use invalid to remove a field
sub setGlobalField(fieldName as String, fieldValue as Dynamic)
  ' ? "Ref App >>> Utils::setGlobalField(fieldName=";fieldName;", fieldValue=";fieldValue;")"

  if not m.global.hasField(fieldName) then
    ? "Ref App >>> Utils::setGlobalField() - adding ";fieldName;" to m.global..."
    newField = {}
    newField[fieldName] = fieldValue
    m.global.addFields(newField)
  else
    ? "Ref App >>> Utils::setGlobalField() - updating existing field (";fieldName;") in m.global..."
  end if
end sub

function _isInitialized(value_) as Boolean
  return type(value_) <> "<uninitialized>"
end function

function _isString(value_) as Boolean
  return _isInitialized(value_) and GetInterface(value_, "ifString") <> invalid
end function

function _isInteger(value_) as Boolean
  return _isInitialized(value_) and GetInterface(value_, "ifInt") <> invalid
end function

function _isFloat(value_) as Boolean
  return _isInitialized(value_) and GetInterface(value_, "ifFloat") <> invalid
end function

function _isDouble(value_) as Boolean
  return _isInitialized(value_) and GetInterface(value_, "ifDouble") <> invalid
end function

function _isLongInteger(value_) as Boolean
  return _isInitialized(value_) and GetInterface(value_, "ifLongInt") <> invalid
end function

function _isBoolean(value_ as Dynamic) as Boolean
  return _isInitialized(value_) and GetInterface(value_, "ifBoolean") <> invalid
end function

function _isArray(value_) as Boolean
  return _isInitialized(value_) and GetInterface(value_, "ifArray") <> invalid
end function

function _isObject(value_) as Boolean
  return _isInitialized(value_) and GetInterface(value_, "ifAssociativeArray") <> invalid
end function

function _isNumeric(value_) as Boolean
  if not(_isInitialized(value_)) then
    return false
  end if

  return GetInterface(value_, "ifInt") <> invalid or GetInterface(value_, "ifFloat") <> invalid or GetInterface(value_, "ifLongInt") <> invalid or GetInterface(value_, "ifDouble") <> invalid
end function

function _isScalar(value_) as Boolean
  return _isNumeric(value_) or _isBoolean(value_) or _isString(value_)
end function

function _isFunction(value_) as Boolean
  return _isInitialized(value_) and GetInterface(value_, "ifFunction") <> invalid
end function

function _isEnumerable(value_) as Boolean
  return _isInitialized(value_) and GetInterface(value_, "ifEnum") <> invalid
end function

function _isSGNode(value_) as Boolean
  return _isInitialized(value_) and type(value_) = "roSGNode"
end function

function _isNonEmptyString(value_) as Boolean
  return _isString(value_) and value_.Trim() <> ""
end function

function _isInvalidOrEmptyString(value_) as Boolean
  if not(_isInitialized(value_)) or value_ = invalid then
    return true
  end if

  if _isString(value_) and value_ = "" then
    return true
  end if

  return false
end function

function _asString(value_, fallback_ = "") as String
  if _isInitialized(value_) and value_ <> invalid and GetInterface(value_, "ifToStr") <> invalid then
    return value_.ToStr()
  else
    return fallback_
  end if
end function

function _asFloat(value_) as Float
  if _isNumeric(value_) then
    return value_
  else if _isString(value_) then
    return value_.toFloat()
  end if

  return 0.0
end function

function _asInteger(value_ as Dynamic, fallback_ = 0) as Integer
  if not(_isInitialized(value_)) then
    return fallback_
  end if

  if _isString(value_) then
    return Val(value_, 0)
  end if

  if _isNumeric(value_) then
    return value_
  end if

  return fallback_
end function

function _asLongInteger(value_) as LongInteger
  if _isLongInteger(value_) or _isInteger(value_) then
    return 0& + value_
  else if _isString(value_) and value_.Trim() <> "" then
    return ParseJSON("[" + value_ + "]")[0]
  end if

  return 0&
end function

function _Math_Min(a_ as Float, b_ as Float) as Float
  if a_ > b_ then
    return b_
  else
    return a_
  end if
end function

function _Math_Max(a_ as Float, b_ as Float) as Float
  if a_ > b_ then
    return a_
  else
    return b_
  end if
end function

function _Math_Ceil(value_) as Integer
  if Int(value_) = value_ then
    result_ = value_
  else
    result_ = Int(value_) + 1
  end if

  return result_
end function

function _Math_Floor(value_) as Integer
  return Int(value_)
end function

function _Math_Round(value_) as Integer
  return Cint(value_)
end function
