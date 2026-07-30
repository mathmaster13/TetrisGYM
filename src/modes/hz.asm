; hz stuff

; hz = 60.098 * (taps - 1) / (frames - 1)
; PAL is 50.006
;
; HydrantDude explains how and why the formula works here: https://discord.com/channels/374368504465457153/405470199400235013/867156217259884574


;; combo of the V6 and Jonas Cup ROMs. THIS IS NOT IDIOMATIC ASSEMBLY, because I don't know how to write that.

; TODO figure out what hzSpawnDelay does in V6. it may be a debug thing but I had JC skip it.

hzDebounceThreshold := $10

hzStart: ; called in playState_spawnNextTetrimino, gameModeState_initGameState, gameMode_gameTypeMenu
        lda #0
        sta hzTapCounter
        sta tapBufferButtons ; only used in JC, copied from JC
        ; TODO for some reason, in JC, hzDebounceThreshold is put into the buffer. no clue why, but it is nonsense imo
        lda #hzDebounceThreshold
        sta hzDebounceCounter
        ; V6: frame counter is reset on first tap.
        ; I think it's fine to reset it on first tap for JC as well.
        ; TODO test that. speedtest should always use v6 first tap
        rts

hzControl: ; called in playState_playerControlsActiveTetrimino, gameTypeLoopContinue, speedTestControl
;; all common to both implementations
        lda hzTapCounter
        beq @notTapping
        ; tick frame counter
        lda hzFrameCounter
        clc
        adc #$01
        sta hzFrameCounter
        lda #$00
        adc hzFrameCounter+1
        sta hzFrameCounter+1
@notTapping:
; common
        ; tick debounce counter
        lda hzDebounceCounter
        cmp #hzDebounceThreshold
        beq @elapsed
        inc hzDebounceCounter
@elapsed:
; switch on V6/JC
        lda jonasCupFlag
        bne @jonasCupDetectInputs
; V6
        ; detect inputs
        lda newlyPressedButtons_player1
        and #BUTTON_LEFT+BUTTON_RIGHT
        cmp #BUTTON_LEFT
        beq hzTap
        and #BUTTON_LEFT+BUTTON_RIGHT
        cmp #BUTTON_RIGHT
        beq hzTap

        lda hzTapCounter
        bne @noDelayInc
        lda hzSpawnDelay
        cmp #$F
        bcs @noDelayInc
        inc hzSpawnDelay
@noDelayInc:
        rts

;; JC version
@jonasCupDetectInputs:
        lda tapBufferButtons    ; keep previous tap buffer state in X
        tax
        lda newlyPressedButtons_player1
        and #BUTTON_LEFT+BUTTON_RIGHT
        sta tapBufferButtons    ; set prospective early tap buffer state
        bne hzTap               ; if there's a fresh tap on this frame, process it now
        txa                     ; if there's a 1-frame buffer tap, then mux it in
        bne @bufferTapped
        rts
@bufferTapped:
        sta tapBufferButtons    ; use tap buffer as a tmp var for muxing
        lda newlyPressedButtons ; the _player1 variable does NOT work because shift_tetrimino does not check it!
        and #$FF-BUTTON_LEFT-BUTTON_RIGHT ; get non-horizontal tapped buttons
        ora tapBufferButtons    ; combine
        sta newlyPressedButtons
        lda #$00
        sta tapBufferButtons    ; clear buffer
        lda newlyPressedButtons ; set up A as appropriate for @tapped logic
        and #BUTTON_LEFT+BUTTON_RIGHT
hzTap:
        clc
        ror             ; normalize direction to 1/0
        tax             ; keep button direction in X to free up A
        lda jonasCupFlag
        beq :+          ; SOCD override is for Jonas Cup only.

        ; Jonas Cup SOCD logic.

        lda heldButtons_player1 ; SOCD 40Hz override: if both are held, dir = Right
        and #BUTTON_LEFT+BUTTON_RIGHT
        cmp #BUTTON_LEFT+BUTTON_RIGHT
        bne :+
        lda #$00        ; right
        tax

: ; common
        cpx hzTapDirection
        bne @fresh
        ; if debouncing meets threshold, this is a fresh tap
        lda hzDebounceCounter
        cmp #hzDebounceThreshold
        bne @within
@fresh:
        stx hzTapDirection
@wrap:
        lda #0
        sta hzTapCounter
        sta hzFrameCounter+1
        ; 0 is the first frame (4 means 5 frames)
        sta hzFrameCounter
@within:
        ; in Gym impl: increment tap count here to measure taps
        ; in CTWC rework: instrument tap count increment directly in shift_tetrimino to measure movements
        ; Both: reset debounce
        ; on V6/speedtest, we will increment afterward.
        lda hzTapCounter
        cmp #$10
        bcs @wrap
        lda #0
        sta hzDebounceCounter

        lda #0
        sta dasOnlyShiftDisabled

; DAS only mode stuff; skip it if we aren't in DAS mode.
; Speed test is not DAS mode, since it never was in V6,
        lda practiseType
        cmp #MODE_SPEED_TEST
        beq @clearBuffer
        lda dasOnlyFlag
        beq @clearBuffer ; clear buffer and return

        lda #$08
        clc
        adc jonasCupFlag ; only JC is allowed to use the last table entry
        tax
        clc
        cpx hzTapCounter
        bcc @disableShift
        ; TODO this is a very lazy fix to deal with the different limits of the two systems. Pick a better one.
        ldx hzTapCounter
        lda jonasCupFlag
        bne @checkForPAL
        clc
        txa
        adc #$14
        tax
@checkForPAL:
        lda palFlag
        beq @NTSCDASOnly
        clc
        txa
        adc #$A
        tax
@NTSCDASOnly:
        lda dasLimitLookup, x
        cmp hzFrameCounter
        bmi @clearBuffer      ; if tap is allowed, clear 1-frame buffer and return
@disableShift:
        lda #1
        sta dasOnlyShiftDisabled

        lda jonasCupFlag
        beq @incAndRet
        ; on JC ROM, if tap is precisely 1-frame early, keep the tap buffer
        ; else, clear the tap buffer
        lda dasLimitLookup, x
        cmp hzFrameCounter
        beq @ret ; we are on JC so do not inc the tap counter
@clearBuffer:
        lda #$00
        sta tapBufferButtons
        lda practiseType
        cmp #MODE_SPEED_TEST
        beq @incAndRet
        lda jonasCupFlag
        bne @ret ; return
@incAndRet:
        inc hzTapCounter
        jmp calculate_hz ; hz gets computed here
@ret:
        rts

calculate_hz: ; done after any taps are done
        ; ignore 1 tap
        lda hzTapCounter
        cmp #2
        bcc @calcEnd

        ; TODO in JC mode, ignore 2taps where the first tap is DAS

        lda #$7A
        sta factorB24
        lda #$17
        sta factorB24+1
        lda #0
        sta factorA24+1
        sta factorA24+2
        sta factorB24+2

        lda hzTapCounter
        sbc #1
        sta factorA24

        lda palFlag
        beq @notPAL
        lda #$89
        sta factorB24
        lda #$13
        sta factorB24+1
@notPAL:

        jsr unsigned_mul24

        ; taps-1 * 6010 now in product24

        lda product24
        sta dividend
        lda product24+1
        sta dividend+1
        lda product24+2
        sta dividend+2

        ; then divide by the hzFrameCounter, which should be frames-1

        lda hzFrameCounter
        sta divisor
        lda hzFrameCounter+1
        sta divisor+1
        lda #0
        sta divisor+2

        jsr unsigned_div24 ; hz*100 in dividend

        ldx dividend+1 ; get hz for palette
        lda hzPaletteGradient, x
        sta hzPalette

        lda dividend
        sta binary32
        lda dividend+1
        sta binary32+1
        lda dividend+2
        sta binary32+2
        lda #0
        sta binary32+3

        jsr BIN_BCD ; hz*100 as BCD in bcd32

        lda bcd32
        sta hzResult+1
        lda bcd32+1
        sta hzResult

@calcEnd:

        ; update game UI
        lda renderFlags
        ora #RENDER_HZ
        sta renderFlags
        rts

; X: value to store if left or right is newly pressed
checkNegativeDelay:
        ; the tail of entry delay has two paths: a normal path, and one where
        ; spawn delay is added (currently, tspins and debug mode)
        ; if the spawn delay is too large, we shouldn't update here
        lda spawnDelay
        cmp #3
        bcs @ret
        lda hzSpawnDelay
        bne @ret
        lda newlyPressedButtons_player1
        and #BUTTON_LEFT+BUTTON_RIGHT
        cmp #BUTTON_LEFT
        beq @setDelay
        lda newlyPressedButtons_player1
        and #BUTTON_LEFT+BUTTON_RIGHT
        cmp #BUTTON_RIGHT
        beq @setDelay
        rts
@setDelay:
        stx hzSpawnDelay
        lda renderFlags
        ora #$10
        sta renderFlags
@ret:
        rts

dasLimitLookup: ; JC table.
        .byte $FF, $FF, 11, 17, 23, 29, 35, 41 , 47, 53 ;, 59
        .byte $FF, $FF, 7, 11, 15, 19, 23, 27, 31, 35 ; PAL
        ; V6 table TODO decide on something less lazy than this to implement the differences.
        .byte $FF, 3, 10, 17, 23, 29, 35, 41 , 47, 53 ;, 59
        .byte $FF, 2, 6, 11, 15, 19, 23, 27, 31, 35 ; PAL


; Kitaru on reddit - Thankfully, the same "round-down" effect also benefits DAS speed. Whereas the NTSC DAS timings were 16f start-up and 6f period, PAL DAS timings are 12f start-up and 4f period. Accounting for framerate, this is an improvement from NTSC DAS's real-time rate of 10Hz vs. PAL's real-time rate of 12.5Hz. So, although PAL hits its max gravity at Level 19 instead of Level 29, the boosted DAS makes it a bit more survivable. PAL DAS can still be out-tapped, albeit at a slimmer margin.

hzPaletteGradient: ; goes up to B
        .byte $16, $26, $27, $28, $29, $2a, $2c, $22, $23, $24, $14, $15
