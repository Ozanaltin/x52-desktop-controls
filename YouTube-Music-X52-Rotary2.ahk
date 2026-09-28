#Requires AutoHotkey v2.0
#SingleInstance Force

; YouTube Music Desktop App + Logitech X52 Pro controls.
;
; Rotary 2 fully left  = 0%
; Rotary 2 centre      = approximately 50%
; Rotary 2 fully right = 100%
; Clutch button        = start a new Windows screen snip
; Both controls work only while Inactive.pr0 is the active X52 profile.
;
; First launch: YTMDesktop will ask you to authorize this controller once.
; The authorization token is stored beside this script in YTM-X52-Volume.ini.

A_HotkeyInterval := 0

; ---- Adjustable settings ---------------------------------------------------
REVERSE_ROTARY := false       ; JoyV reports left = 0 and right = 100.
VOLUME_STEP := 1              ; 1 = every percentage; 2 = two-percent increments.
AXIS_NOISE_FLOOR := 0.50      ; Ignores tiny X52 potentiometer jitter.
ENDPOINT_SNAP := 1.0          ; Snaps the physical ends cleanly to 0% and 100%.
POLL_INTERVAL_MS := 10        ; Reads the rotary with minimal perceived delay.
FINAL_SETTLE_MS := 70         ; Sends the exact value shortly after motion stops.
LIVE_UPDATE_MS := 650         ; Preview rate during a long continuous turn.
MIN_REQUEST_GAP_MS := 550     ; YTMDesktop allows only 2 commands per second.
X52_NUMBER := 1               ; Confirmed controller number on this system.
ROTARY_2_AXIS := "JoyV"       ; Confirmed X52 Rotary 2 axis on this system.
REQUIRED_X52_PROFILE := "Inactive.pr0"
PROFILE_CHECK_MS := 250       ; How quickly profile changes enable/disable controls.

; ---- YTMDesktop Companion Server ------------------------------------------
API_BASE := "http://127.0.0.1:9863/api/v1"
APP_ID := "ozanarathx52volume"
APP_NAME := "Ozanarath X52 Volume Control"
APP_VERSION := "1.0.0"
CONFIG_FILE := A_ScriptDir "\YTM-X52-Volume.ini"
YTM_TOKEN := IniRead(CONFIG_FILE, "YTMDesktop", "Token", "")

; ---- Runtime state ---------------------------------------------------------
ROTARY_2_KEY := X52_NUMBER ROTARY_2_AXIS
LastRawAxisValue := 0.0
DesiredVolume := -1
LastSentVolume := -1
LastMovementTick := 0
MovementStartTick := 0
LastRequestTick := -10000
NextRetryTick := 0
SendingVolume := false
X52ControlsEnabled := false
X52_PROFILE_HANDLE := 0

OnExit CloseX52ProfileDevice
RefreshX52ProfileState()
SetTimer WatchRotary2, POLL_INTERVAL_MS
SetTimer ProcessDesiredVolume, POLL_INTERVAL_MS
SetTimer RefreshX52ProfileState, PROFILE_CHECK_MS

; X52 Pro clutch / "i" button. The X52 is controller 1 and the clutch is Joy31.
; KeyWait and the cooldown guarantee only one snip for each physical press.
1Joy31::{
    global X52ControlsEnabled
    static lastSnipTick := -10000

    ; Recheck the driver at the moment of the press, rather than relying only
    ; on the periodic profile check.
    RefreshX52ProfileState()
    if !X52ControlsEnabled
        return

    if (A_TickCount - lastSnipTick < 1000)
        return

    lastSnipTick := A_TickCount
    SendEvent "{LWin down}{LShift down}s{LShift up}{LWin up}"
    KeyWait "1Joy31"
}

WatchRotary2() {
    global ROTARY_2_KEY, LastRawAxisValue, AXIS_NOISE_FLOOR
    global X52ControlsEnabled

    if (!X52ControlsEnabled || ROTARY_2_KEY = "")
        return

    currentValue := GetKeyState(ROTARY_2_KEY)
    if !IsNumber(currentValue)
        return

    if Abs(currentValue - LastRawAxisValue) < AXIS_NOISE_FLOOR
        return

    ; Verify the active profile again before accepting an actual movement.
    if !RefreshX52ProfileState()
        return

    LastRawAxisValue := currentValue
    QueueAxisVolume(currentValue)
}

QueueAxisVolume(axisValue, force := false) {
    global REVERSE_ROTARY, VOLUME_STEP, ENDPOINT_SNAP
    global DesiredVolume, LastMovementTick, MovementStartTick, FINAL_SETTLE_MS
    global X52ControlsEnabled

    if !X52ControlsEnabled
        return

    volume := REVERSE_ROTARY ? 100 - axisValue : axisValue

    if (volume <= ENDPOINT_SNAP)
        volume := 0
    else if (volume >= 100 - ENDPOINT_SNAP)
        volume := 100

    volume := Round(volume / VOLUME_STEP) * VOLUME_STEP
    volume := Max(0, Min(100, volume))

    if (!force && volume = DesiredVolume)
        return

    now := A_TickCount

    if (LastMovementTick = 0 || now - LastMovementTick >= FINAL_SETTLE_MS)
        MovementStartTick := now

    DesiredVolume := volume
    LastMovementTick := now
}

ProcessDesiredVolume() {
    global DesiredVolume, LastSentVolume, SendingVolume
    global LastMovementTick, MovementStartTick, LastRequestTick, NextRetryTick
    global FINAL_SETTLE_MS, LIVE_UPDATE_MS, MIN_REQUEST_GAP_MS
    global X52ControlsEnabled

    if (!X52ControlsEnabled || DesiredVolume < 0
        || DesiredVolume = LastSentVolume || SendingVolume)
        return

    now := A_TickCount

    if (now < NextRetryTick || now - LastRequestTick < MIN_REQUEST_GAP_MS)
        return

    stoppedMoving := now - LastMovementTick >= FINAL_SETTLE_MS
    longContinuousMove := now - MovementStartTick >= LIVE_UPDATE_MS
        && now - LastRequestTick >= LIVE_UPDATE_MS

    if (!stoppedMoving && !longContinuousMove)
        return

    ; This final driver query prevents a queued volume change from being sent
    ; after the user has switched away from Inactive.pr0.
    if !RefreshX52ProfileState()
        return

    volumeToSend := DesiredVolume
    SendingVolume := true
    LastRequestTick := now

    result := SendYTMCommand("setVolume", volumeToSend)

    if (result.Status >= 200 && result.Status < 300) {
        LastSentVolume := volumeToSend
        NextRetryTick := 0
    } else if (result.Status = 429) {
        NextRetryTick := A_TickCount + GetRetryDelay(result.Headers)
    } else {
        NextRetryTick := A_TickCount + 1000
    }

    SendingVolume := false
}

SendYTMCommand(command, data?) {
    global API_BASE, YTM_TOKEN

    ; Defer first-time authorization until the allowed X52 profile actually
    ; causes a YouTube Music command.
    if (YTM_TOKEN = "")
        AuthorizeYTMDesktop()

    if IsSet(data)
        body := '{"command":"' command '","data":' data '}'
    else
        body := '{"command":"' command '"}'

    return HttpPost(API_BASE "/command", body, YTM_TOKEN)
}

GetRetryDelay(headers) {
    if RegExMatch(headers, "im)^Retry-After:\s*(\d+)", &match)
        return Max(1000, match[1] * 1000)

    return 1100
}

; ---- Active X52 profile gate ----------------------------------------------
; Logitech's X52 driver exposes the active .pr0 path through its programmable
; device interface. Reading the driver is more reliable than checking whether
; a profile file merely exists or trying to infer state from the tray icon.

RefreshX52ProfileState() {
    global REQUIRED_X52_PROFILE, X52ControlsEnabled, ROTARY_2_KEY
    global LastRawAxisValue, DesiredVolume, LastSentVolume
    global LastMovementTick, MovementStartTick, NextRetryTick

    Critical

    try activeProfile := GetActiveX52Profile()
    catch
        activeProfile := ""

    profileFile := RegExReplace(Trim(activeProfile), "^.*[\\/]")
    enabledNow := profileFile != ""
        && StrLower(profileFile) = StrLower(REQUIRED_X52_PROFILE)

    if (enabledNow = X52ControlsEnabled)
        return enabledNow

    X52ControlsEnabled := enabledNow

    ; Discard work queued by the previous profile. When Inactive.pr0 becomes
    ; active, start from the rotary's current absolute position.
    DesiredVolume := -1
    LastSentVolume := -1
    LastMovementTick := 0
    MovementStartTick := 0
    NextRetryTick := 0

    if (enabledNow && ROTARY_2_KEY != "") {
        currentValue := GetKeyState(ROTARY_2_KEY)
        if IsNumber(currentValue) {
            LastRawAxisValue := currentValue
            QueueAxisVolume(currentValue, true)
        }
    }

    return enabledNow
}

GetActiveX52Profile() {
    global X52_PROFILE_HANDLE

    if !X52_PROFILE_HANDLE
        X52_PROFILE_HANDLE := OpenX52ProfileDevice()

    if !X52_PROFILE_HANDLE
        return ""

    ; IOCTL 2570: ask whether a profile is active. Logitech checks all four
    ; returned bytes, so this script does the same.
    activeState := Buffer(4, 0)
    if !ProfileDeviceIoControl(
        X52_PROFILE_HANDLE, 0x222828, 0, 0,
        activeState, activeState.Size, &activeBytes
    ) {
        CloseX52ProfileDevice()
        return ""
    }

    profileIsActive := false
    Loop 4 {
        if NumGet(activeState, A_Index - 1, "UChar") {
            profileIsActive := true
            break
        }
    }

    if !profileIsActive
        return ""

    ; IOCTL 2561: obtain the active profile path. This packet layout mirrors
    ; the Logitech driver's own GetActiveProfile implementation.
    requestData := Buffer(8, 0)
    NumPut "UChar", 1, requestData, 3

    Loop 4
        NumPut "UChar", NumGet(activeState, A_Index - 1, "UChar"),
            requestData, A_Index + 3

    profileData := Buffer(1024, 0)
    if !ProfileDeviceIoControl(
        X52_PROFILE_HANDLE, 0x222804,
        requestData, requestData.Size,
        profileData, profileData.Size, &profileBytes
    ) {
        CloseX52ProfileDevice()
        return ""
    }

    ; Logitech decodes the entire fixed buffer and trims its NULL padding;
    ; do the same because some driver builds do not report a useful byte count.
    characterCount := Floor((profileData.Size - 6) / 2)
    return Trim(StrGet(profileData.Ptr + 6, characterCount, "UTF-16"))
}

OpenX52ProfileDevice() {
    ; This is the programmable-device interface GUID used by Logitech's X52
    ; software (internally named the Toronto device).
    interfaceGuid := Buffer(16, 0)
    if DllCall(
        "Ole32\CLSIDFromString",
        "WStr", "{0C244C6F-2C78-4F0C-A036-8DB0E9012B27}",
        "Ptr", interfaceGuid,
        "Int"
    ) != 0
        return 0

    for devicePath in GetPresentDeviceInterfaces(interfaceGuid) {
        handle := DllCall(
            "Kernel32\CreateFileW",
            "WStr", devicePath,
            "UInt", 0xC0000000, ; GENERIC_READ | GENERIC_WRITE
            "UInt", 3,          ; FILE_SHARE_READ | FILE_SHARE_WRITE
            "Ptr", 0,
            "UInt", 3,          ; OPEN_EXISTING
            "UInt", 0x80,       ; FILE_ATTRIBUTE_NORMAL
            "Ptr", 0,
            "Ptr"
        )

        if (!handle || handle = -1)
            continue

        ; Only keep a path that accepts the Logitech profile-state request.
        testState := Buffer(4, 0)
        if ProfileDeviceIoControl(
            handle, 0x222828, 0, 0,
            testState, testState.Size, &testBytes
        )
            return handle

        DllCall "Kernel32\CloseHandle", "Ptr", handle
    }

    return 0
}

GetPresentDeviceInterfaces(interfaceGuid) {
    paths := []

    ; CM_GET_DEVICE_INTERFACE_LIST_PRESENT is zero. Retry once in case the
    ; device list changes between the size query and the data query.
    Loop 2 {
        characterCount := 0
        result := DllCall(
            "CfgMgr32\CM_Get_Device_Interface_List_SizeW",
            "UInt*", &characterCount,
            "Ptr", interfaceGuid,
            "Ptr", 0,
            "UInt", 0,
            "UInt"
        )

        if (result != 0 || characterCount < 2)
            return paths

        pathList := Buffer(characterCount * 2, 0)
        result := DllCall(
            "CfgMgr32\CM_Get_Device_Interface_ListW",
            "Ptr", interfaceGuid,
            "Ptr", 0,
            "Ptr", pathList,
            "UInt", characterCount,
            "UInt", 0,
            "UInt"
        )

        if (result != 0)
            continue

        offset := 0
        while (offset < characterCount) {
            devicePath := StrGet(pathList.Ptr + offset * 2, "UTF-16")
            if (devicePath = "")
                break

            paths.Push(devicePath)
            offset += StrLen(devicePath) + 1
        }

        return paths
    }

    return paths
}

ProfileDeviceIoControl(
    handle, controlCode, inputBuffer, inputSize,
    outputBuffer, outputSize, &bytesReturned
) {
    bytesReturned := 0
    inputPointer := inputSize ? inputBuffer.Ptr : 0

    return DllCall(
        "Kernel32\DeviceIoControl",
        "Ptr", handle,
        "UInt", controlCode,
        "Ptr", inputPointer,
        "UInt", inputSize,
        "Ptr", outputBuffer,
        "UInt", outputSize,
        "UInt*", &bytesReturned,
        "Ptr", 0,
        "Int"
    )
}

CloseX52ProfileDevice(*) {
    global X52_PROFILE_HANDLE

    if X52_PROFILE_HANDLE {
        DllCall "Kernel32\CloseHandle", "Ptr", X52_PROFILE_HANDLE
        X52_PROFILE_HANDLE := 0
    }
}

AuthorizeYTMDesktop() {
    global API_BASE, APP_ID, APP_NAME, APP_VERSION
    global CONFIG_FILE, YTM_TOKEN

    requestBody := '{"appId":"' APP_ID '","appName":"' APP_NAME '","appVersion":"' APP_VERSION '"}'

    codeResult := HttpPost(API_BASE "/auth/requestcode", requestBody)
    if (codeResult.Status < 200 || codeResult.Status >= 300) {
        MsgBox "Could not contact YTMDesktop Companion Server.`n`n"
            . "Confirm that YTMDesktop is running and Companion Server is enabled, then restart this script.`n`n"
            . "HTTP status: " codeResult.Status,
            "X52 YouTube Music volume", "Iconx"
        ExitApp
    }

    if !RegExMatch(codeResult.Body, '"code"\s*:\s*"([^"]+)"', &codeMatch) {
        MsgBox "YTMDesktop did not return an authorization code.",
            "X52 YouTube Music volume", "Iconx"
        ExitApp
    }

    MsgBox "YTMDesktop will now ask whether to authorize:`n`n"
        . APP_NAME "`n`nApprove it inside YTMDesktop within 30 seconds, then return here.",
        "Authorize X52 volume control", "Iconi"

    tokenBody := '{"appId":"' APP_ID '","code":"' codeMatch[1] '"}'
    tokenResult := HttpPost(API_BASE "/auth/request", tokenBody, "", 35000)

    if (tokenResult.Status < 200 || tokenResult.Status >= 300
        || !RegExMatch(tokenResult.Body, '"token"\s*:\s*"([^"]+)"', &tokenMatch)) {
        MsgBox "Authorization was not completed.`n`nRestart the script and approve the request inside YTMDesktop.",
            "X52 YouTube Music volume", "Iconx"
        ExitApp
    }

    YTM_TOKEN := tokenMatch[1]
    IniWrite YTM_TOKEN, CONFIG_FILE, "YTMDesktop", "Token"

    MsgBox "Authorization complete.`n`nRotary 2 now controls YTMDesktop from 0% to 100%.",
        "X52 YouTube Music volume", "Iconi"
}

HttpPost(url, body, authorization := "", receiveTimeout := 5000) {
    try {
        request := ComObject("WinHttp.WinHttpRequest.5.1")
        request.SetTimeouts(5000, 5000, 5000, receiveTimeout)
        request.Open("POST", url, false)
        request.SetRequestHeader("Content-Type", "application/json")

        if (authorization != "")
            request.SetRequestHeader("Authorization", authorization)

        request.Send(body)
        headers := request.GetAllResponseHeaders()
        return {Status: request.Status, Body: request.ResponseText, Headers: headers}
    } catch Error as err {
        return {Status: 0, Body: err.Message, Headers: ""}
    }
}