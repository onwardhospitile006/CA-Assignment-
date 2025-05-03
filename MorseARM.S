.syntax unified
        .cpu cortex-m0
        .thumb

        .equ GPIO_BASE,    0x50000000
        .equ RADIO_BASE,   0x40001000
        .equ TIMER0_BASE,  0x40008000
        .equ SYSTICK_CTRL, 0xE000E010
        .equ SYSTICK_LOAD, 0xE000E014

        .equ PIN_A,        (1 << 17)      @ P0.17 = Button A
        .equ PIN_B,        (1 << 26)      @ P0.26 = Button B

        @ RADIO register offsets
        .equ RADIO_FREQUENCY, 0x504
        .equ GPIO_IN,        0x514

        .data
morse_codes:
        @ Table of pointers to dot‑dash strings
        .word code_dot       @ "."
        .word code_dash      @ "-"
        .word code_dot_dash  @ ".-"
        .word 0              @ Zero terminator for table
morse_letters:
        .byte 'E','T','A',0   @ matching above entries; ending zero

code_dot:
        .asciz "."
code_dash:
        .asciz "-"
code_dot_dash:
        .asciz ".-"
        @ … rest of your patterns

        .bss
        .align 4
buf_sym: 
        .space 32            @ buffer for current symbol (max length 31 + 0)
buf_idx:
        .word 0

        @ System tick counter
ms_counter:
        .word 0

        .text
        .global main
main:
        @ --- Initialize SysTick for millisecond timing ---
        LDR   R0, =SYSTICK_LOAD
        LDR   R1, =(16000-1)    @ SysTick at 16 MHz → 1 ms ticks
        STR   R1, [R0]
        LDR   R0, =SYSTICK_CTRL
        MOVS  R1, #3           @ ENABLE + TICKINT
        STR   R1, [R0]

        @ --- Init RADIO (shortened) ---
        LDR   R0, =RADIO_BASE
        MOVS  R1, #1           @ channel/group 1
        LDR   R2, =RADIO_FREQUENCY
        STR   R1, [R0, R2]     @ RADIO.FREQUENCY
        @ … more RADIO setup omitted for brevity …

main_loop:                      @ Renamed from 'loop' to avoid confusion with other loops
        BL    check_incoming
        BL    read_buttons

        @ If returned R0=1 (A), R1=0 (not B) → dot/dash
        @ If R0 and R1 both 1 → both hold; handle short/long
        CMP   R0, #1
        BNE   check_b
        CMP   R1, #0
        BEQ   only_a
        B     both_pressed

check_b:
        CMP   R1, #1
        BEQ   only_b
        B     main_loop         @ Changed from 'loop' to 'main_loop'

only_a:
        BL    add_dash
        B     main_loop         @ Changed from 'loop' to 'main_loop'

only_b:
        BL    add_dot
        B     main_loop         @ Changed from 'loop' to 'main_loop'

both_pressed:
        BL    both_hold
        B     main_loop         @ Changed from 'loop' to 'main_loop'

@------------- subroutines -------------

@ Read GPIO pins into R0=A_state, R1=B_state
read_buttons:
        PUSH  {R2, R3, LR}      @ Added LR to save return address
        LDR   R2, =GPIO_BASE
        LDR   R3, =GPIO_IN
        LDR   R3, [R2, R3]     @ IN register
        MOVS  R0, #0
        MOVS  R1, #0
        LDR   R2, =PIN_A
        ANDS  R2, R3, R2
        BEQ   check_pin_b
        MOVS  R0, #1
check_pin_b:
        LDR   R2, =PIN_B
        ANDS  R2, R3, R2
        BEQ   read_done
        MOVS  R1, #1
read_done:
        POP   {R2, R3, PC}      @ Changed to PC for return
        @ BX LR not needed with POP {regs, PC}

@ Append '-' to buf
add_dash:
        PUSH  {R0-R3, LR}       @ Added LR to save all used registers
        LDR   R0, =buf_idx
        LDR   R1, [R0]
        CMP   R1, #31
        BCS   add_dash_done     @ Renamed label to be more specific
        LDR   R2, =buf_sym
        ADDS  R2, R2, R1
        MOVS  R3, #'-'
        STRB  R3, [R2]
        ADDS  R1, R1, #1
        STR   R1, [R0]
add_dash_done:                  @ Renamed label to be more specific
        POP   {R0-R3, PC}       @ Changed to PC for return

@ Append '.' to buf
add_dot:
        PUSH  {R0-R3, LR}       @ Added LR to save all used registers
        LDR   R0, =buf_idx
        LDR   R1, [R0]
        CMP   R1, #31
        BCS   add_dot_done      @ Renamed label to be more specific
        LDR   R2, =buf_sym
        ADDS  R2, R2, R1
        MOVS  R3, #'.'
        STRB  R3, [R2]
        ADDS  R1, R1, #1
        STR   R1, [R0]
add_dot_done:                   @ Renamed label to be more specific
        POP   {R0-R3, PC}       @ Changed to PC for return

@ Handle both buttons held: classify short vs long
both_hold:
        PUSH  {R0-R4, LR}       @ Save all used registers
        BL    get_ms
        MOVS  R4, R0            @ start time
both_wait_release:              @ Renamed label to be more specific
        BL    read_buttons
        MOVS  R2, R0
        ORRS  R2, R1
        CMP   R2, #0            @ Changed BNE to explicit comparison
        BNE   both_wait_release @ wait until neither pressed
        BL    get_ms
        SUBS  R0, R0, R4        @ duration
        MOVS  R1, #150          @ Compare with 1500ms (split into 150 * 10)
        MOVS  R2, #10
        MULS  R1, R2, R1
        CMP   R0, R1
        BLS   short_hold        @ <= 1.5s
        BL    transmit_word     @ > 1.5s
        B     both_hold_done    @ Renamed label to be more specific
short_hold:
        BL    end_letter
both_hold_done:                 @ Renamed label to be more specific
        POP   {R0-R4, PC}       @ Changed to PC for return

@ On short hold: finalize one letter
end_letter:
        PUSH  {R0-R3, LR}       @ Save all used registers
        LDR   R0, =buf_sym      @ Make sure buf_sym is null-terminated
        LDR   R1, =buf_idx
        LDR   R2, [R1]
        CMP   R2, #31           @ Safety check
        BGT   end_letter_skip
        MOVS  R3, #0
        STRB  R3, [R0, R2]      @ Null-terminate
end_letter_skip:
        LDR   R0, =buf_sym
        BL    decode_symbol     @ returns letter in R0
        @ (Here you'd append R0 to the decoded word buffer & display it)
        @ Clear buf_idx
        LDR   R1, =buf_idx
        MOVS  R2, #0
        STR   R2, [R1]
        POP   {R0-R3, PC}       @ Changed to PC for return

@ On long hold: send over radio
transmit_word:
        PUSH  {R0-R3, LR}       @ Save used registers
        @ (Here you'd read your decoded‑word buffer, send via RADIO, then clear it)
        @ For brevity, omitted the full RADIO.TX sequence—but you'd:
        @   - Write payload pointer & length to PACKETPTR & MAXLEN
        @   - Trigger TASKS_TXEN, then TASKS_START
        @   - Wait for EVENTS_END
        POP   {R0-R3, PC}       @ Changed to PC for return

@ Decode current buf_sym into a letter in R0
decode_symbol:
        PUSH  {R1-R3, LR}       @ Save used registers
        LDR   R1, =morse_codes
        LDR   R2, =morse_letters
decode_loop_table:              @ Renamed label to be more specific
        LDR   R3, [R1]          @ get next code ptr
        CMP   R3, #0            @ Check if we've reached the end of the table
        BEQ   not_found
        PUSH  {R1, R2}          @ Save registers before calling strcmp
        LDR   R0, [R1]          @ R0 = ptr to code string
        LDR   R1, =buf_sym      @ R1 = ptr to current symbol buffer
        BL    strcmp            @ compare with buf_sym
        POP   {R1, R2}          @ Restore registers after strcmp
        CMP   R0, #0            @ equal?
        BEQ   match             @ If equal (R0=0), we found a match
        ADDS  R1, #4            @ advance to next code ptr
        ADDS  R2, #1            @ advance letter ptr
        B     decode_loop_table
match:
        LDRB  R0, [R2]          @ fetch letter
        B     done_decode
not_found:
        MOVS  R0, #'?'          @ unknown
done_decode:
        @ Clear buf_idx
        LDR   R3, =buf_idx
        MOVS  R1, #0
        STR   R1, [R3]
        POP   {R1-R3, PC}       @ Changed to PC for return

@ strcmp: R0 = pointer A, R1 = pointer B
@ Returns: R0 = 0 if equal, 1 if different
strcmp:
        PUSH  {R2-R5, LR}       @ Save used registers
        MOVS  R4, R0            @ preserve pointers
        MOVS  R5, R1
strcmp_loop:                    @ Renamed label to be more specific
        LDRB  R2, [R4]          @ load char from string A
        LDRB  R3, [R5]          @ load char from string B
        CMP   R2, R3
        BNE   str_diff
        CMP   R2, #0            @ Check if we've reached the end of the string
        BEQ   str_eq
        ADDS  R4, #1            @ increment pointer A
        ADDS  R5, #1            @ increment pointer B
        B     strcmp_loop
str_diff:
        MOVS  R0, #1
        B     str_done
str_eq:
        MOVS  R0, #0
str_done:
        POP   {R2-R5, PC}       @ Changed to PC for return

@ Return milliseconds since reset in R0
get_ms:
        PUSH  {R1, R2, LR}
        LDR   R0, =ms_counter
        LDR   R0, [R0]          @ Get current counter value directly
        
        @ Increment counter (could be done by SysTick handler, but this works too)
        LDR   R1, =ms_counter
        LDR   R2, [R1]
        ADDS  R2, #1            @ increment
        STR   R2, [R1]
        
        POP   {R1, R2, PC}      @ Changed to PC for return

@ Stub: check for incoming radio packet
check_incoming:
        PUSH  {LR}
        @ Add functionality here if needed
        POP   {PC}              @ Changed to PC for return

        .end
