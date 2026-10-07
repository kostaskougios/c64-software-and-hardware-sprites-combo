; Character-mode comparison build. BASIC SYS 2064.
* = $0801
    !byte $0c,$08,$0a,$00,$9e,$20,$32,$30,$36,$34,$00,$00,$00
* = $0810

VIC_CTRL1      = $d011
VIC_CTRL2      = $d016
VIC_MEM        = $d018
VIC_RASTER     = $d012
VIC_BG         = $d021
VIC_IRQ_FLAGS  = $d019
VIC_IRQ_MASK   = $d01a
SCREEN         = $4400
SCREEN_BACK    = $4c00
MapPtr         = $02
SourceRowPtr   = $04
ScreenRowPtr   = $06
ColorRowPtr    = $08
ColorSourcePtr = $0a
HistoryXPtr    = $0c
HistoryYPtr    = $0e
FontPtr        = $10
BaseGlyphPtr   = $12
MaskGlyphPtr   = $14
DestGlyphPtr   = $16

Start:
    sei
    lda $01
    and #$f8
    ora #$06
    sta $01                     ; expose RAM at $a000 while keeping I/O and KERNAL
    lda #$00
    sta $d020
    lda #$06
    sta VIC_BG                  ; code 00 sky fill; raster IRQ changes it for the city
    lda $dd02
    ora #$03
    sta $dd02
    lda $dd00
    and #$fc
    ora #$02
    sta $dd00                  ; VIC bank 1 ($4000-$7fff)

    ; Install the generated 256-glyph multicolor character set at $5800.
    ldx #$00
CopyGlyphPage:
    !for .page, 0, 7 {
        lda CharacterGlyphs + .page * $100,x
        sta $5800 + .page * $100,x
        sta $6000 + .page * $100,x
    }
    inx
    bne CopyGlyphPage

    ; One screen code and one color per 8x8 background cell.
    ldx #$00
CopyScreenPage:
    !for .page, 0, 2 {
        lda CharacterScreen + .page * $100,x
        sta SCREEN + .page * $100,x
        sta SCREEN_BACK + .page * $100,x
        lda CharacterColors + .page * $100,x
        sta $d800 + .page * $100,x
    }
    inx
    bne CopyScreenPage
    ldx #$00
CopyScreenTail:
    lda CharacterScreen + $300,x
    sta SCREEN + $300,x
    sta SCREEN_BACK + $300,x
    lda CharacterColors + $300,x
    sta $d800 + $300,x
    inx
    cpx #$e8
    bne CopyScreenTail

    ; 25-row multicolor character mode, screen $4400, charset $5800.
    lda #$1b
    sta VIC_CTRL1
    lda #$18                  ; multicolor: code 00 background, code 10 black ink
    sta VIC_CTRL2
    lda #$00
    sta $d023                 ; multicolor code 10 shared color (black)
    lda #$0e
    sta $d022                 ; code 01 unused
    lda #$16
    sta VIC_MEM
    ldx #$00
CopyCharacterSpritePage:
    lda CharacterSpriteData,x
    sta $5000,x
    inx
    bne CopyCharacterSpritePage
    jsr InitSprites
    jsr SortActors
    lda #$00
    sta BackBuffer
    lda #$16
    sta VIC_MEM
    jsr DrawCharacterOutlines
    jsr SaveActorPositions
    jsr PositionAllSprites
    lda #$18
    sta VIC_CTRL2               ; sprite setup must not leave hires text selected
    lda #$16
    sta VIC_MEM
    lda #$01
    sta BackBuffer
    lda #$00
    sta RasterPhase
    lda #<BackgroundRasterIRQ
    sta $0314
    lda #>BackgroundRasterIRQ
    sta $0315
    lda #$32                   ; raster 50: reset the sky color each frame
    sta VIC_RASTER
    lda #$01
    sta VIC_IRQ_FLAGS           ; clear any pending raster interrupt
    lda VIC_IRQ_MASK
    ora #$01
    sta VIC_IRQ_MASK
    cli
    jmp CharacterFrame

; Switch the code-00 background color at the skyline. Black linework and the
; moving outline use code 10, colored with the shared $d023 register.
BackgroundRasterIRQ:
    lda VIC_IRQ_FLAGS
    and #$01
    beq BackgroundRasterDone
    lda #$01
    sta VIC_IRQ_FLAGS
    lda RasterPhase
    bne BackgroundCityLine
    lda #$06
    sta VIC_BG
    lda #$7a                   ; raster 122: city begins 72 pixels below screen top
    sta VIC_RASTER
    lda #$01
    sta RasterPhase
    jmp $ea31
BackgroundCityLine:
    lda #$0e
    sta VIC_BG
    lda #$32
    sta VIC_RASTER
    lda #$00
    sta RasterPhase
BackgroundRasterDone:
    jmp $ea31

CharacterFrame:
    jsr RestoreActorCells
    jsr MoveActors
    jsr SortActors
    jsr DrawCharacterOutlines
    jsr SaveActorPositions
    jsr WaitFrame
    lda #$18
    sta VIC_CTRL2               ; reassert multicolor text mode at frame boundary
    lda BackBuffer
    beq ShowScreen1
    lda #$38
    bne SelectVisibleScreen
ShowScreen1:
    lda #$16
SelectVisibleScreen:
    sta VIC_MEM
    lda BackBuffer
    eor #$01
    sta BackBuffer
    jsr PositionAllSprites
    jmp CharacterFrame

InitSprites:
    lda #$ff
    sta $d015
    sta $d01c
    sta $d01d                  ; 2x width: 48 pixels
    sta $d017
    lda #$ff
    sta $d01b                  ; black character ink overlays sprites; code-00 fill stays behind
    lda #$0f
    sta $d025                  ; shared light-grey sprite color
    lda #$0c
    sta $d026                  ; shared medium-grey makes the third color distinct
    lda #$00
    sta $d010
    ; Patterns are also copied to the matching offset in bank 3.
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
    sta SCREEN_BACK+$3f8,x
    lda SpriteColors,x
    sta $d027,x
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
    ldx ActorIndex
    txa
    and #$03
    tax
    ldy SpriteSlot
    lda SpritePointers,x
    sta SCREEN+$3f8,y
    sta SCREEN_BACK+$3f8,y
    ldx ActorIndex
    lda SpriteColors,x
    ldx SpriteSlot
    sta $d027,x
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
    ldx SpriteSlot
    lda $d010
    and ClearXmsb,x
    sta $d010
    ldx ActorIndex
    lda ActorX,x
    clc
    adc #$18
    bcc PositionDone
    ldx SpriteSlot
    lda $d010
    ora SetXmsb,x
    sta $d010
PositionDone:
    rts

; Restore the previous outline cells on the hidden screen page from the static
; background before drawing the actor contours at their new positions.
RestoreActorCells:
    jsr SelectActorHistory
    beq RestoreActorCellsDone
    lda #$01
    sta CellMode
    jsr UpdateActorCellGrid
RestoreActorCellsDone:
    rts

SelectActorHistory:
    lda BackBuffer
    beq SelectHistory0
    lda #<PreviousActorX1
    sta HistoryXPtr
    lda #>PreviousActorX1
    sta HistoryXPtr+1
    lda #<PreviousActorY1
    sta HistoryYPtr
    lda #>PreviousActorY1
    sta HistoryYPtr+1
    lda PreviousValid1
    rts
SelectHistory0:
    lda #<PreviousActorX0
    sta HistoryXPtr
    lda #>PreviousActorX0
    sta HistoryXPtr+1
    lda #<PreviousActorY0
    sta HistoryYPtr
    lda #>PreviousActorY0
    sta HistoryYPtr+1
    lda PreviousValid0
    rts

UpdateActorCellGrid:
    lda #$00
    sta ActorIndex
UpdateActorCellActor:
    ldx ActorIndex
    lda CellMode
    beq CellUseCurrent
    txa
    tay
    lda (HistoryXPtr),y
    sta CellPixelX
    lda (HistoryYPtr),y
    sta CellPixelY
    jmp CellActorPositionReady
CellUseCurrent:
    lda ActorX,x
    sta CellPixelX
    lda ActorY,x
    sta CellPixelY
CellActorPositionReady:
    lda CellPixelX
    lsr
    lsr
    lsr
    sec
    sbc #$01                   ; include the contour cell left of the sprite
    sta BaseCellX
    lda CellPixelY
    lsr
    lsr
    lsr
    sec
    sbc #$01                   ; include the contour row above the sprite
    sta BaseCellY
    lda #$00
    sta CellRow
CellGridRow:
    lda BaseCellY
    clc
    adc CellRow
    sta RowIndex
    jsr SetRowPointers
    lda #$00
    sta CellColumn
CellGridColumn:
    lda BaseCellX
    clc
    adc CellColumn
    tay
    lda CellMode
    beq CellBlankForSprite
    lda (SourceRowPtr),y
    sta (ScreenRowPtr),y
    lda (ColorSourcePtr),y
    sta (ColorRowPtr),y
    jmp CellGridColumnDone
CellBlankForSprite:
    lda #$00
    sta (ScreenRowPtr),y
CellGridColumnDone:
    inc CellColumn
    lda CellColumn
    cmp #$08
    bne CellGridColumn
    inc CellRow
    lda CellRow
    cmp #$08
    bne CellGridRow
    inc ActorIndex
    lda ActorIndex
    cmp #$08
    beq UpdateActorCellGridDone
    jmp UpdateActorCellActor
UpdateActorCellGridDone:
    rts

DrawCharacterOutlines:
    lda #$20
    sta NextCompositeCode       ; dynamic composite glyphs occupy codes 32-255
    lda BackBuffer
    beq DrawFont1
    lda #$60
    bne DrawFontReady
DrawFont1:
    lda #$58
DrawFontReady:
    sta FontPtr+1
    lda #$00
    sta FontPtr
    lda #$00
    sta DrawOrderIndex
DrawCharacterActor:
    ldx DrawOrderIndex
    lda RenderOrder,x
    sta ActorIndex
    tax
    lda ActorX,x
    sta CellPixelX
    and #$04
    lsr
    lsr
    asl
    asl
    asl
    sta OutlineVariant
    lda ActorY,x
    sta CellPixelY
    and #$07
    clc
    adc OutlineVariant
    sta OutlineVariant
    lda CellPixelX
    lsr
    lsr
    lsr
    sec
    sbc #$01
    sta BaseCellX
    lda CellPixelY
    lsr
    lsr
    lsr
    sec
    sbc #$01
    sta BaseCellY
    ldx ActorIndex
    txa
    and #$03
    asl
    asl
    asl
    asl
    clc
    adc OutlineVariant
    tax
    lda CharacterOutlineLo,x
    sta MapPtr
    lda CharacterOutlineHi,x
    sta MapPtr+1
    lda #$00
    sta CellRow
    sta MapOffset
DrawOutlineRow:
    lda BaseCellY
    clc
    adc CellRow
    sta RowIndex
    jsr SetRowPointers
    lda #$00
    sta CellColumn
DrawOutlineColumn:
    ldy MapOffset
    lda (MapPtr),y
    beq OutlineCellEmpty
    sta OutlineChar
    iny
    lda (MapPtr),y
    sta OutlineCharHi
    lda BaseCellX
    clc
    adc CellColumn
    tay
    sty TargetCellOffset
    jsr ComposeOutlineCell
    ldy TargetCellOffset
OutlineCellEmpty:
    lda MapOffset
    clc
    adc #$02
    sta MapOffset
    inc CellColumn
    lda CellColumn
    cmp #$08
    bne DrawOutlineColumn
    inc CellRow
    lda CellRow
    cmp #$08
    bne DrawOutlineRow
    inc DrawOrderIndex
    lda DrawOrderIndex
    cmp #$08
    beq DrawCharacterOutlinesDone
    jmp DrawCharacterActor
DrawCharacterOutlinesDone:
    rts

; Compose a moving black contour mask over the original background glyph. Each
; screen buffer has its own charset, so only the hidden page is modified.
ComposeOutlineCell:
    lda (ScreenRowPtr),y
    cmp #$20
    bcs ExistingComposite
    sta BackgroundCode
    lda NextCompositeCode
    beq ComposeCellDone        ; exhausted scratch glyphs; preserve the cell
    sta CompositeCode
    inc NextCompositeCode
    lda BackgroundCode
    jsr PointAtBackgroundGlyph
    jmp ComposePointersReady
ExistingComposite:
    sta CompositeCode
    lda CompositeCode
    jsr PointAtFontGlyph
    lda DestGlyphPtr
    sta BaseGlyphPtr
    lda DestGlyphPtr+1
    sta BaseGlyphPtr+1        ; merge another actor's contour in this cell
ComposePointersReady:
    lda OutlineChar
    jsr PointAtContourGlyph
    lda CompositeCode
    jsr PointAtFontGlyph
    ldy TargetCellOffset
    lda CompositeCode
    sta (ScreenRowPtr),y
    ldy #$00
ComposeGlyphRow:
    lda (MaskGlyphPtr),y
    sta MaskByte
    lda (BaseGlyphPtr),y
    sta GlyphByte
    ldx #$00
ComposeGlyphPair:
    lda MaskByte
    and PairInk,x
    beq ComposePairNext
    lda GlyphByte
    and PairClear,x
    ora PairInk,x
    sta GlyphByte
ComposePairNext:
    inx
    cpx #$04
    bne ComposeGlyphPair
    lda GlyphByte
    sta (DestGlyphPtr),y
    iny
    cpy #$08
    bne ComposeGlyphRow
ComposeCellDone:
    rts

PointAtBackgroundGlyph:
    ; CharacterGlyphs is page-aligned and each character occupies eight bytes.
    asl
    asl
    asl
    clc
    adc #$00
    sta BaseGlyphPtr
    lda BackgroundCode
    lsr
    lsr
    lsr
    lsr
    lsr
    clc
    adc #$20
    sta BaseGlyphPtr+1
    rts

PointAtContourGlyph:
    ; Contour IDs are 16-bit because the 2x silhouette needs 425 distinct masks.
    asl
    asl
    asl
    sta MaskGlyphPtr
    lda OutlineChar
    lsr
    lsr
    lsr
    lsr
    lsr
    sta TempMaskPage
    lda OutlineCharHi
    asl
    asl
    asl
    clc
    adc TempMaskPage
    clc
    adc #>CharacterContourGlyphs
    sta MaskGlyphPtr+1
    rts

PointAtFontGlyph:
    asl
    asl
    asl
    sta DestGlyphPtr
    lda CompositeCode
    lsr
    lsr
    lsr
    lsr
    lsr
    clc
    adc FontPtr+1
    sta DestGlyphPtr+1
    rts

SetRowPointers:
    ldx RowIndex
    lda CharacterRowLo,x
    sta SourceRowPtr
    lda CharacterRowHi,x
    sta SourceRowPtr+1
    lda BackBuffer
    beq SetScreen1Row
    lda Screen2RowLo,x
    sta ScreenRowPtr
    lda Screen2RowHi,x
    sta ScreenRowPtr+1
    jmp SetScreenRowDone
SetScreen1Row:
    lda Screen1RowLo,x
    sta ScreenRowPtr
    lda Screen1RowHi,x
    sta ScreenRowPtr+1
SetScreenRowDone:
    lda ColorRowLo,x
    sta ColorSourcePtr
    lda ColorRowHi,x
    sta ColorSourcePtr+1
    lda ColorRamRowLo,x
    sta ColorRowPtr
    lda ColorRamRowHi,x
    sta ColorRowPtr+1
    rts

SaveActorPositions:
    jsr SelectActorHistory
    ldx #$00
SaveActorPositionLoop:
    txa
    tay
    lda ActorX,x
    sta (HistoryXPtr),y
    lda ActorY,x
    sta (HistoryYPtr),y
    inx
    cpx #$08
    bne SaveActorPositionLoop
    lda BackBuffer
    beq SaveHistory0Valid
    lda #$01
    sta PreviousValid1
    rts
SaveHistory0Valid:
    lda #$01
    sta PreviousValid0
    rts

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
    lda #$04
    sta VelX,x
    lda #MinX
    sta ActorX,x
CheckRight:
    lda ActorX,x
    cmp #MaxX
    bcc MoveY
    lda #$fc
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

; This version reuses the same designs, depth sort and movement as the bitmap
; demo. Background and moving contours share the multicolor character layer.
MinX = 16
MaxX = 252
MinY = 20
MaxY = 136
SpritePointers: !byte $40,$41,$42,$43,$40,$41,$42,$43
SpriteColors: !byte $01,$05,$0d,$0a,$03,$07,$0e,$08
ClearXmsb: !byte $fe,$fd,$fb,$f7,$ef,$df,$bf,$7f
SetXmsb: !byte $01,$02,$04,$08,$10,$20,$40,$80
ActorX: !byte 20,88,160,228,44,116,184,252
ActorY: !byte 25,32,25,35,94,100,95,88
VelX: !byte 4,$fc,4,$fc,$fc,4,$fc,4
VelY: !byte 2,1,$fe,$ff,$ff,2,1,$fe
ActorIndex: !byte 0
SpriteSlot: !byte 0
SortPass: !byte 0
SortIndex: !byte 0
SortPassEnd: !byte 0
SortLeftY: !byte 0
SortTemp: !byte 0
RenderOrder: !fill 8, 0
PreviousActorX0: !fill 8, 0
PreviousActorY0: !fill 8, 0
PreviousActorX1: !fill 8, 0
PreviousActorY1: !fill 8, 0
PreviousValid0: !byte 0
PreviousValid1: !byte 0
BackBuffer: !byte 0
RasterPhase: !byte 0
CellMode: !byte 0
CellPixelX: !byte 0
CellPixelY: !byte 0
BaseCellX: !byte 0
BaseCellY: !byte 0
CellRow: !byte 0
CellColumn: !byte 0
RowIndex: !byte 0
OutlineVariant: !byte 0
OutlineChar: !byte 0
OutlineCharHi: !byte 0
TempMaskPage: !byte 0
MapOffset: !byte 0
DrawOrderIndex: !byte 0
NextCompositeCode: !byte 0
BackgroundCode: !byte 0
CompositeCode: !byte 0
TargetCellOffset: !byte 0
MaskByte: !byte 0
GlyphByte: !byte 0
PairInk: !byte $80,$20,$08,$02
PairClear: !byte $3f,$cf,$f3,$fc

CharacterRowLo:
    !for .row, 0, 24 { !byte <(CharacterScreen + .row * 40) }
CharacterRowHi:
    !for .row, 0, 24 { !byte >(CharacterScreen + .row * 40) }
Screen1RowLo:
    !for .row, 0, 24 { !byte <(SCREEN + .row * 40) }
Screen1RowHi:
    !for .row, 0, 24 { !byte >(SCREEN + .row * 40) }
Screen2RowLo:
    !for .row, 0, 24 { !byte <(SCREEN_BACK + .row * 40) }
Screen2RowHi:
    !for .row, 0, 24 { !byte >(SCREEN_BACK + .row * 40) }
ColorRowLo:
    !for .row, 0, 24 { !byte <(CharacterColors + .row * 40) }
ColorRowHi:
    !for .row, 0, 24 { !byte >(CharacterColors + .row * 40) }
ColorRamRowLo:
    !for .row, 0, 24 { !byte <($d800 + .row * 40) }
ColorRamRowHi:
    !for .row, 0, 24 { !byte >($d800 + .row * 40) }

* = $2000
!source "src/generated_characters.asm"
* = $5000
!source "src/generated_sprites.asm"
