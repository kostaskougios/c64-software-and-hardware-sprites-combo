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
PointPtr = $02                  ; unused KERNAL/BASIC zero-page workspace
Ptr = $04

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
    jsr PositionAllSprites
    cli

Frame:
    ; Draw into the hidden bank. Bank 3's $e000 bitmap is under KERNAL ROM,
    ; so temporarily map the ROM out while reading/writing that buffer.
    lda BackBitmapHi
    cmp #$e0
    bne RenderBack
    sei
    lda $01
    sta SavedCpuPort
    and #$fd
    sta $01
    jsr CopyBackgroundToBack
    jsr DrawActors
    lda SavedCpuPort
    sta $01
    cli
    jmp RenderComplete
RenderBack:
    jsr CopyBackgroundToBack
    jsr DrawActors
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
    stx ActorIndex
DrawActor:
    ldx ActorIndex
    lda ActorX,x
    sta BaseX
    lda ActorY,x
    sta BaseY
    jsr DrawOutline
    ldx ActorIndex
    inx
    stx ActorIndex
    cpx #$08
    bne DrawActor
    rts

; ---------------------------------------------------------------------------
; Public routine: DrawOutline
; Inputs: BaseX and BaseY are unsigned bitmap coordinates for the top-left of
;         the 48x42 colour sprite (X 0..271, Y 0..158).
; Clobbers: A, X, Y, Ptr, point cursor and count. Output: contour is ORed
;           into the hires bitmap. Call after clearing/restoring the background.
; ---------------------------------------------------------------------------
DrawOutline:
    lda #<OutlineData
    sta PointPtr
    lda #>OutlineData
    sta PointPtr+1
    lda #OutlineCount
    sta PointsLeft
    lda #$00
    sta PointsLeft+1
    jsr DrawPointList
    ldx ActorIndex
    txa
    and #$03                    ; four character drawings are shared by eight actors
    tax
    lda DetailDataLo,x
    sta PointPtr
    lda DetailDataHi,x
    sta PointPtr+1
    lda DetailCounts,x
    sta PointsLeft
    lda #$00
    sta PointsLeft+1
    jsr DrawPointList
    rts

DrawPointList:
    lda PointsLeft
    ora PointsLeft+1
    beq DrawPointListDone
DrawPoint:
    ldy #$00
    lda (PointPtr),y
    clc
    adc BaseX
    sta PixelX
    lda #$00
    adc #$00
    sta PixelXHi
    inc PointPtr
    bne DrawPointXReady
    inc PointPtr+1
DrawPointXReady:
    lda (PointPtr),y
    clc
    adc BaseY
    sta PixelY
    inc PointPtr
    bne DrawPointYReady
    inc PointPtr+1
DrawPointYReady:
    jsr PlotPixel
    lda PointsLeft
    bne DrawPointDecLow
    dec PointsLeft+1
DrawPointDecLow:
    dec PointsLeft
    lda PointsLeft
    ora PointsLeft+1
    bne DrawPoint
DrawPointListDone:
    rts

; Public routine: PlotPixel
; Inputs: PixelX (low byte), PixelXHi (0 or 1), PixelY (0..199).
;         Together the X inputs describe coordinates 0..319.
; Clobbers: A, X, Y, Ptr. Pixels are black over the colored bitmap background.
PlotPixel:
    ; Bitmap bytes are stored as 8x8 character cells, not scanline rows:
    ; base + (Y/8)*320 + (X/8)*8 + (Y mod 8).
    ldy PixelY
    lda RowLo,y
    sta Ptr
    lda RowHi,y
    clc
    adc BackBitmapHi
    sta Ptr+1
    ; Add (X/8)*8, which is X rounded down to a multiple of eight.
    lda PixelX
    and #$f8
    clc
    adc Ptr
    sta Ptr
    bcc PlotNoXCarry
    inc Ptr+1
PlotNoXCarry:
    lda PixelXHi
    beq PlotColumnReady
    inc Ptr+1                   ; X=256..319 adds the ninth-bit column
PlotColumnReady:
    lda PixelX
    and #$07
    tax
    lda BitMask,x
    ldy #$00
    ora (Ptr),y
    sta (Ptr),y
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
    ldx #$00
PositionAllLoop:
    stx ActorIndex
    jsr PositionSprite
    ldx ActorIndex
    inx
    cpx #$08
    bne PositionAllLoop
    rts

PositionSprite:
    ; VIC screen origin differs from bitmap origin by (24,50).
    ldx ActorIndex
    txa
    asl
    tay
    lda ActorX,x
    clc
    adc #$18
    sta $d000,y
    lda ActorY,x
    clc
    adc #$32
    sta $d001,y
    ; Rebuild the X high-bit register for all eight live sprites.
    lda VIC_SPR_XMSB
    and ClearXmsb,x
    sta VIC_SPR_XMSB
    lda ActorX,x
    clc
    adc #$18
    bcc PositionDone
    lda VIC_SPR_XMSB
    ora SetXmsb,x
    sta VIC_SPR_XMSB
PositionDone:
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
BitMask: !byte $80,$40,$20,$10,$08,$04,$02,$01
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
VelX:           !byte 2,$fe,1,$ff,$fe,2,$ff,1
VelY:           !byte 2,1,$fe,$ff,$ff,2,1,$fe
ActorIndex:     !byte 0
BaseX:          !byte 0
BaseY:          !byte 0
PixelX:         !byte 0
PixelXHi:       !byte 0
PixelY:         !byte 0
PointsLeft:     !word 0
BackBitmapHi:   !byte $e0
BackBank:       !byte $00
SavedCpuPort:   !byte $37

; Static background source data fits in unused RAM below the two VIC banks.
* = $2000
!source "src/generated_background.asm"

; Sprite pages are in VIC bank 1 RAM, outside bitmap and screen memory.
* = $5000
!source "src/generated_sprites.asm"
