; BASIC stub: SYS 2064
* = $0801
    !byte $0c,$08,$0a,$00,$9e,$20,$32,$30,$36,$34,$00,$00,$00
* = $0810

; VIC-II bank 1 is the front bitmap ($6000/$4400); bank 3 is the back bitmap
; ($e000/$c400). Both banks have RAM visible throughout, including sprite data.
VIC_SPR_ENABLE = $d015
VIC_SPR_XMSB   = $d010
VIC_CTRL1      = $d011
VIC_CTRL2      = $d016
VIC_MEM        = $d018
VIC_RASTER     = $d012
VIC_SPR_MCOLOR = $d01c
VIC_SPR_XEXP   = $d01d
VIC_SPR_YEXP   = $d017
VIC_SPR_PRIORITY = $d01b
VIC_BG         = $d021
VIC_MC0        = $d025
VIC_MC1        = $d026
VIC_SPR0_COLOR = $d027
SCREEN         = $4400
SCREEN_BACK    = $c400
MinX = 16
MaxX = 255
MinY = 20
MaxY = 136
SourcePtr = $02                 ; unused KERNAL/BASIC zero-page workspace
Ptr = $04
ShiftRightPtr = $06
ShiftLeftPtr = $08

Start:
    sei
    lda #$00
    sta $d020                   ; border black
    sta VIC_BG
    ; Select VIC bank 1: $4000-$7fff, with both CIA2 bank-select pins outputs.
    lda $dd02
    ora #$03
    sta $dd02
    lda $dd00
    and #$fc
    ora #$02
    sta $dd00
    lda #$0f
    sta VIC_MC0                 ; light grey feature fill under hires ink
    lda #$02
    sta VIC_MC1                 ; red
    lda #$ff
    sta VIC_SPR_PRIORITY        ; hires foreground detail draws over all eight sprites

    ; Hires bitmap mode, 320x200. Screen RAM $4400, bitmap $6000.
    lda #$3b
    sta VIC_CTRL1
    lda #$08
    sta VIC_CTRL2
    lda #$18
    sta VIC_MEM

    jsr InitScreenColors
    jsr InitSprites
    lda #$60
    sta BackBitmapHi
    jsr CopyBackgroundToBack
    lda #$e0
    sta BackBitmapHi
    jsr CopyBackgroundToBack
    lda #$00
    sta BackBank               ; bank 3 is the first back buffer
    jsr SortActors
    jsr PositionAllSprites
    cli

Frame:
    jsr SortActors
    ; Draw into the hidden bank. Bank 3's $e000 bitmap is under KERNAL ROM,
    ; so temporarily map the ROM out while clearing/drawing that buffer.
    lda BackBitmapHi
    cmp #$e0
    bne RenderBack
    sei
    lda $01
    sta SavedCpuPort
    and #$fd
    sta $01
    jsr ClearBackBitmap
    jsr DrawActors
    lda SavedCpuPort
    sta $01
    cli
    jmp RenderComplete
RenderBack:
    ; The shift lookup pages live under BASIC ROM. Disable BASIC while keeping
    ; the KERNAL and I/O visible so raster interrupts continue to work.
    lda $01
    sta SavedCpuPort
    and #$fe
    sta $01
    jsr ClearBackBitmap
    jsr DrawActors
    lda SavedCpuPort
    sta $01
RenderComplete:
    ; Swap only at the bottom border. The visible bitmap remains intact while
    ; the next frame is composed in the other bank.
    jsr WaitFrame
    jsr PositionAllSprites
    lda $dd00
    and #$fc
    ora BackBank
    sta $dd00
    lda BackBank
    eor #$02
    sta BackBank
    lda BackBitmapHi
    eor #$80
    sta BackBitmapHi
    jsr MoveActors
    jmp Frame

DrawActors:
    ldx #$00
    stx DrawOrderIndex
DrawActor:
    ldx DrawOrderIndex
    lda RenderOrder,x
    sta ActorIndex
    tax
    lda ActorX,x
    sta BaseX
    lda ActorY,x
    sta BaseY
    jsr CheckActorOverlap
    lda OverlapFlag
    beq DrawActorOutline
    jsr ClearBitmapUnderActor
DrawActorOutline:
    jsr DrawOutline
    inc DrawOrderIndex
    lda DrawOrderIndex
    cmp #$08
    bne DrawActor
    rts

; A silhouette only needs to erase contours when an earlier (farther) actor's
; 48x42 bounding box intersects it. Most frames have few such intersections.
CheckActorOverlap:
    lda #$00
    sta OverlapFlag
    lda DrawOrderIndex
    beq ActorOverlapDone
    ldx ActorIndex
    lda ActorX,x
    sta CurrentActorX
    lda ActorY,x
    sta CurrentActorY
    lda #$00
    sta OverlapScanIndex
ActorOverlapLoop:
    ldx OverlapScanIndex
    lda RenderOrder,x
    tax
    lda ActorX,x
    sta OtherActorX
    lda ActorY,x
    sta OtherActorY
    ; Horizontal interval overlap: absolute X distance must be less than 48.
    lda CurrentActorX
    cmp OtherActorX
    bcc ActorOverlapXReverse
    sec
    sbc OtherActorX
    cmp #$30
    bcs ActorOverlapNext
    jmp ActorOverlapCheckY
ActorOverlapXReverse:
    lda OtherActorX
    sec
    sbc CurrentActorX
    cmp #$30
    bcs ActorOverlapNext
ActorOverlapCheckY:
    ; Vertical interval overlap: absolute Y distance must be less than 42.
    lda CurrentActorY
    cmp OtherActorY
    bcc ActorOverlapYReverse
    sec
    sbc OtherActorY
    cmp #$2a
    bcs ActorOverlapNext
    jmp ActorOverlapFound
ActorOverlapYReverse:
    lda OtherActorY
    sec
    sbc CurrentActorY
    cmp #$2a
    bcs ActorOverlapNext
ActorOverlapFound:
    lda #$01
    sta OverlapFlag
    rts
ActorOverlapNext:
    inc OverlapScanIndex
    lda OverlapScanIndex
    cmp DrawOrderIndex
    bne ActorOverlapLoop
ActorOverlapDone:
    rts

; Clear a farther actor's outline under this actor's opaque silhouette, then
; draw this actor's own contour. Transparent parts leave farther contours intact.
ClearBitmapUnderActor:
    lda #$01
    sta MaskMode
    ldx ActorIndex
    txa
    and #$03
    tax
    lda SilhouetteDataLo,x
    sta SourcePtr
    lda SilhouetteDataHi,x
    sta SourcePtr+1
    jmp DrawActorMaskRows

DrawOutline:
    lda #$00
    sta MaskMode
    ldx ActorIndex
    txa
    and #$03
    tax
    lda ContourDataLo,x
    sta SourcePtr
    lda ContourDataHi,x
    sta SourcePtr+1
    jmp DrawActorMaskRows

; Draw or erase a precombined 48x42 mask, shifted for arbitrary actor X.
DrawActorMaskRows:
    lda BaseX
    and #$07
    sta HorizontalShift
    beq MaskShiftTablesReady
    ; Each shift amount occupies its own lookup page.
    clc
    adc #>(ShiftRightTable-1)
    sta ShiftRightPtr+1
    lda HorizontalShift
    clc
    adc #>(ShiftLeftTable-1)
    sta ShiftLeftPtr+1
MaskShiftTablesReady:
    lda #<ShiftRightTable
    sta ShiftRightPtr
    lda #<ShiftLeftTable
    sta ShiftLeftPtr
    lda #$00
    sta MaskRow
DrawMaskRow:
    ldy #$00
LoadMaskByte:
    lda (SourcePtr),y
    sta RowScratch,y
    iny
    cpy #$06
    bne LoadMaskByte
    lda #$00
    sta RowScratch+6
    ldx HorizontalShift
    bne DoMaskShift
    jmp MaskShifted
DoMaskShift:
    ; The VIC's left-to-right pixel order carries each byte's low bit into
    ; bit 7 of the next byte when shifted right. Preserve that carry per byte.
    ldy RowScratch
    lda (ShiftRightPtr),y
    sta ShiftOut
    ldy RowScratch
    lda (ShiftLeftPtr),y
    sta ShiftCarry
    lda ShiftOut
    sta RowScratch
    ldy RowScratch+1
    lda (ShiftRightPtr),y
    ora ShiftCarry
    sta ShiftOut
    ldy RowScratch+1
    lda (ShiftLeftPtr),y
    sta ShiftCarry
    lda ShiftOut
    sta RowScratch+1
    ldy RowScratch+2
    lda (ShiftRightPtr),y
    ora ShiftCarry
    sta ShiftOut
    ldy RowScratch+2
    lda (ShiftLeftPtr),y
    sta ShiftCarry
    lda ShiftOut
    sta RowScratch+2
    ldy RowScratch+3
    lda (ShiftRightPtr),y
    ora ShiftCarry
    sta ShiftOut
    ldy RowScratch+3
    lda (ShiftLeftPtr),y
    sta ShiftCarry
    lda ShiftOut
    sta RowScratch+3
    ldy RowScratch+4
    lda (ShiftRightPtr),y
    ora ShiftCarry
    sta ShiftOut
    ldy RowScratch+4
    lda (ShiftLeftPtr),y
    sta ShiftCarry
    lda ShiftOut
    sta RowScratch+4
    ldy RowScratch+5
    lda (ShiftRightPtr),y
    ora ShiftCarry
    sta ShiftOut
    ldy RowScratch+5
    lda (ShiftLeftPtr),y
    sta ShiftCarry
    lda ShiftOut
    sta RowScratch+5
    lda ShiftCarry
    sta RowScratch+6
MaskShifted:
    lda BaseY
    clc
    adc MaskRow
    tay
    lda RowLo,y
    sta Ptr
    lda RowHi,y
    clc
    adc BackBitmapHi
    sta Ptr+1
    lda BaseX
    and #$f8
    clc
    adc Ptr
    sta Ptr
    bcc MaskRowAddressReady
    inc Ptr+1
MaskRowAddressReady:
    ; Screen bytes in a bitmap row are eight bytes apart. Keep the row base
    ; fixed and use Y as the byte offset instead of rebuilding Ptr seven times.
    lda MaskMode
    bne EraseMaskRow
    ldx #$00
    ldy #$00
DrawMaskByte:
    lda RowScratch,x
    beq SkipMaskByte
    ora (Ptr),y
    sta (Ptr),y
SkipMaskByte:
    tya
    clc
    adc #$08
    tay
    inx
    cpx #$07
    bne DrawMaskByte
    jmp MaskBytesDone

EraseMaskRow:
    ldx #$00
    ldy #$00
EraseMaskByte:
    lda RowScratch,x
    beq SkipEraseMaskByte
    lda RowScratch,x
    eor #$ff
    and (Ptr),y
    sta (Ptr),y
SkipEraseMaskByte:
    tya
    clc
    adc #$08
    tay
    inx
    cpx #$07
    bne EraseMaskByte
MaskBytesDone:
    clc
    lda SourcePtr
    adc #$06
    sta SourcePtr
    bcc MaskSourceReady
    inc SourcePtr+1
MaskSourceReady:
    inc MaskRow
    lda MaskRow
    cmp #$2a
    beq DrawMaskDone
    jmp DrawMaskRow
DrawMaskDone:
    rts

InitScreenColors:
    ldx #$00
ColorPage:
    lda BackgroundColors,x
    sta SCREEN,x
    sta SCREEN_BACK,x
    lda BackgroundColors+$100,x
    sta SCREEN+$100,x
    sta SCREEN_BACK+$100,x
    lda BackgroundColors+$200,x
    sta SCREEN+$200,x
    sta SCREEN_BACK+$200,x
    lda BackgroundColors+$300,x
    sta SCREEN+$300,x
    sta SCREEN_BACK+$300,x
    inx
    bne ColorPage
    rts

CopyBackgroundToBack:
    lda BackBitmapHi
    cmp #$60
    beq CopyToBank1
    jmp CopyToBank3
CopyToBank1:
    ldx #$00
CopyToBank1Column:
    !for .page, $20, $3f {
        lda .page * $100,x
        sta (.page + $40) * $100,x
    }
    inx
    beq CopyToBank1Done
    jmp CopyToBank1Column
CopyToBank1Done:
    rts
CopyToBank3:
    ldx #$00
CopyToBank3Column:
    !for .page, $20, $3f {
        lda .page * $100,x
        sta (.page + $c0) * $100,x
    }
    inx
    beq CopyToBank3Done
    jmp CopyToBank3Column
CopyToBank3Done:
    rts

; The hidden bitmap is normally blank; clear it before recompositing actors.
ClearBackBitmap:
    lda BackBitmapHi
    cmp #$60
    beq ClearToBank1
    lda #$00
    ldx #$00
ClearToBank3Column:
    !for .page, $e0, $ff {
        sta .page * $100,x
    }
    inx
    beq ClearToBank3Done
    jmp ClearToBank3Column
ClearToBank3Done:
    rts
ClearToBank1:
    lda #$00
    ldx #$00
ClearToBank1Column:
    !for .page, $60, $7f {
        sta .page * $100,x
    }
    inx
    beq ClearToBank1Done
    jmp ClearToBank1Column
ClearToBank1Done:
    rts

InitSprites:
    ; Multicolour + 2x width and height. Install patterns in both VIC banks.
    lda #$ff
    sta VIC_SPR_ENABLE
    sta VIC_SPR_MCOLOR
    sta VIC_SPR_XEXP
    sta VIC_SPR_YEXP
    lda #$00
    sta VIC_SPR_XMSB
    ldx #$00
CopySpritesToBank3:
    lda $5000,x
    sta $c000,x
    inx
    bne CopySpritesToBank3
    ldx #$00
InitSpriteLoop:
    lda SpritePointers,x
    sta SCREEN+$3f8,x
    lda SpritePointersBack,x
    sta SCREEN_BACK+$3f8,x
    lda SpriteColors,x
    sta VIC_SPR0_COLOR,x
    inx
    cpx #$08
    bne InitSpriteLoop
    rts

PositionAllSprites:
    lda #$00
    sta SpriteSlot
PositionAllLoop:
    lda #$07
    sec
    sbc SpriteSlot
    tax
    lda RenderOrder,x
    sta ActorIndex
    jsr PositionSprite
    inc SpriteSlot
    lda SpriteSlot
    cmp #$08
    bne PositionAllLoop
    rts

PositionSprite:
    ; Sprite number determines VIC-II overlap priority: slot 0 is foremost.
    ; Assign nearer actors (largest Y) to lower slots, preserving identity data.
    ldx ActorIndex
    txa
    and #$03
    tax
    ldy SpriteSlot
    lda SpritePointers,x
    sta SCREEN+$3f8,y
    lda SpritePointersBack,x
    sta SCREEN_BACK+$3f8,y
    ldx ActorIndex
    lda SpriteColors,x
    ldx SpriteSlot
    sta VIC_SPR0_COLOR,x
    txa
    asl
    tay
    ldx ActorIndex
    lda ActorX,x
    clc
    adc #$18
    sta $d000,y
    lda ActorY,x
    clc
    adc #$32
    sta $d001,y
    ; Rebuild the X high-bit register for all eight live sprites.
    ldx SpriteSlot
    lda VIC_SPR_XMSB
    and ClearXmsb,x
    sta VIC_SPR_XMSB
    ldx ActorIndex
    lda ActorX,x
    clc
    adc #$18
    bcc PositionDone
    ldx SpriteSlot
    lda VIC_SPR_XMSB
    ora SetXmsb,x
    sta VIC_SPR_XMSB
PositionDone:
    rts

; Stable bubble sort, farthest (smallest Y) to nearest (largest Y).
; The same order composites bitmap outlines and assigns VIC-II sprite priority.
SortActors:
    ldx #$00
SortInitOrder:
    txa
    sta RenderOrder,x
    inx
    cpx #$08
    bne SortInitOrder
    lda #$00
    sta SortPass
SortPassLoop:
    lda #$00
    sta SortIndex
    lda #$07
    sec
    sbc SortPass
    sta SortPassEnd
SortPairLoop:
    ldx SortIndex
    lda RenderOrder,x
    tax
    lda ActorY,x
    sta SortLeftY
    ldx SortIndex
    inx
    lda RenderOrder,x
    tax
    lda ActorY,x
    cmp SortLeftY
    bcs SortNoSwap
    ldx SortIndex
    lda RenderOrder,x
    sta SortTemp
    inx
    lda RenderOrder,x
    dex
    sta RenderOrder,x
    inx
    lda SortTemp
    sta RenderOrder,x
SortNoSwap:
    inc SortIndex
    lda SortIndex
    cmp SortPassEnd
    bcc SortPairLoop
    inc SortPass
    lda SortPass
    cmp #$07
    bne SortPassLoop
    rts

MoveActors:
    ldx #$00
MoveLoop:
    lda ActorX,x
    clc
    adc VelX,x
    sta ActorX,x
    cmp #MinX
    bcs CheckRight
    lda #$01
    sta VelX,x
    lda #MinX
    sta ActorX,x
CheckRight:
    lda ActorX,x
    cmp #MaxX
    bcc MoveY
    lda #$ff
    sta VelX,x
    lda #MaxX
    sta ActorX,x
MoveY:
    lda ActorY,x
    clc
    adc VelY,x
    sta ActorY,x
    cmp #MinY
    bcs CheckBottom
    lda #$01
    sta VelY,x
    lda #MinY
    sta ActorY,x
CheckBottom:
    lda ActorY,x
    cmp #MaxY
    bcc MoveNext
    lda #$ff
    sta VelY,x
    lda #MaxY
    sta ActorY,x
MoveNext:
    inx
    cpx #$08
    bne MoveLoop
    rts

WaitFrame:
    lda #$fa
WaitRaster:
    cmp VIC_RASTER
    bne WaitRaster
WaitRasterEnd:
    cmp VIC_RASTER
    beq WaitRasterEnd
    rts

; Lookup tables are included below the executable routines.
RowLo:
    !for .y, 0, 199 {
        !byte <((.y & $f8)*40 + (.y & $07))
    }
RowHi:
    !for .y, 0, 199 {
        !byte >((.y & $f8)*40 + (.y & $07))
    }

SpritePointers:     !byte $40,$41,$42,$43,$40,$41,$42,$43
SpritePointersBack: !byte $00,$01,$02,$03,$00,$01,$02,$03
SpriteColors:   !byte $01,$05,$0d,$0a,$03,$07,$0e,$08
ClearXmsb:      !byte $fe,$fd,$fb,$f7,$ef,$df,$bf,$7f
SetXmsb:        !byte $01,$02,$04,$08,$10,$20,$40,$80
ActorX:         !byte 18,88,158,228,45,115,185,250
ActorY:         !byte 25,32,25,35,94,100,95,88
CurrentActorX:  !byte 0
CurrentActorY:  !byte 0
OtherActorX:    !byte 0
OtherActorY:    !byte 0
OverlapFlag:    !byte 0
OverlapScanIndex: !byte 0
VelX:           !byte 2,$fe,1,$ff,$fe,2,$ff,1
VelY:           !byte 2,1,$fe,$ff,$ff,2,1,$fe
ActorIndex:     !byte 0
BaseX:          !byte 0
BaseY:          !byte 0
HorizontalShift: !byte 0
MaskRow:        !byte 0
MaskMode:       !byte 0
DrawOrderIndex: !byte 0
SpriteSlot:     !byte 0
SortPass:       !byte 0
SortIndex:      !byte 0
SortPassEnd:    !byte 0
SortLeftY:      !byte 0
SortTemp:       !byte 0
RenderOrder:    !fill 8, 0
RowScratch:     !fill 7, 0
ShiftCarry:     !byte 0
ShiftOut:       !byte 0
BackBitmapHi:   !byte $e0
BackBank:       !byte $00
SavedCpuPort:   !byte $37

; Static background source data fits in unused RAM below the two VIC banks.
* = $2000
!source "src/generated_background.asm"

; Sprite pages are in VIC bank 1 RAM, outside bitmap and screen memory.
* = $5000
!source "src/generated_sprites.asm"

; Seven 256-byte pages per direction make arbitrary 1..7 pixel shifts a pair
; of table reads per mask byte. These reside under BASIC ROM ($a000-$adff).
* = $a000
ShiftRightTable:
    !for .shift, 1, 7 {
        !for .value, 0, 255 {
            !byte (.value >> .shift)
        }
    }
ShiftLeftTable:
    !for .shift, 1, 7 {
        !for .value, 0, 255 {
            !byte ((.value << (8-.shift)) & $ff)
        }
    }
