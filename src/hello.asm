; Standalone emulator check. BASIC SYS 2064 enters the program at $0810.
* = $0801
    !byte $0c,$08,$0a,$00,$9e,$20,$32,$30,$36,$34,$00,$00,$00
* = $0810

Start:
    lda #$00
    sta $d020                   ; black border
    sta $d021                   ; black screen
    lda #$93
    jsr $ffd2                   ; clear screen through KERNAL CHROUT
PrintMessage:
    ldx MessageIndex
    lda Message,x
    beq HoldScreen
    inc MessageIndex
    jsr $ffd2
    jmp PrintMessage
HoldScreen:
    jmp HoldScreen

Message:
    !pet "HELLO WORLD!",13
    !pet "C64 PROGRAM IS RUNNING.",13
    !pet "DIRECT PRG LOAD OK.",0
MessageIndex:
    !byte 0
