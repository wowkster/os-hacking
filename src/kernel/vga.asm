%ifndef PRINT_ASM
%define PRINT_ASM

%include "mem.asm"

VIDEO_MEMORY_ADDR equ 0xB8000
SCREEN_ROWS equ 25
SCREEN_COLS equ 80
SCREEN_CAPACITY equ SCREEN_ROWS * SCREEN_COLS
WHITE_ON_BLACK equ 0x0F

; Static variable to hold our offset into the video memory
_print_offset: dw 0

; 
; Prints a given string into the VGA video memory in text mode
; @input esi - Pointer to the string to print (null terminated)
;
kprint: 
    pushad

    ; If the input is a null pointer, do nothing
    cmp esi, 0
    je .finished

    ; All text will be printed as white on black for now
    mov ah, WHITE_ON_BLACK

    ; ebx will hold our offset
    xor ebx, ebx

    ; Load a character and break if it's null (the end of the string)
    .print_loop:
        lodsb 

        cmp al, 0
        je .finished


    ; If there is enugh room on the screen for the next character, just print it. Otherwise, scroll the screen first
    .scroll_if_needed:
        mov bx, [_print_offset]
        cmp bx, SCREEN_CAPACITY 
        jne .print_char

        call scroll_screen
        mov bx, SCREEN_COLS * (SCREEN_ROWS - 1)

    ; Calculate the correct offset into the video memory and move the character
    .print_char:
        mov [ebx * 2 + VIDEO_MEMORY_ADDR], ax

    ; Increment the print offset, store it back into memory, and continue
    .continue_loop:
        inc bx
        mov [_print_offset], bx
        jmp .print_loop

    .finished:
        popad
        ret

;
; Prints a given string into the VGA video memory in text mode and moves the cursor down to the next line
; @input esi - Pointer to the string to print (null terminated)
;
kprintln:
    pushad

    ; Print the string
    call kprint

    ; If we're at the end of the text buffer, only scroll. Otherwise, move cursor to start of next line
    mov ax, [_print_offset]
    cmp ax, SCREEN_CAPACITY
    jne .move_cursor

    ; Scroll the screen and keep cursor at end of buffer
    .scroll:
        call scroll_screen
        jmp .finished

    ; Move the cursor to the start of the next line
    .move_cursor:
        ; Calculate the index into the current line
        ; dx := _print_offset % SCREEN_COLS
        xor dx, dx
        mov ax, [_print_offset]
        mov bx, SCREEN_COLS
        div bx

        ; Calculate the number of remaining characters in the current line
        ; bx := 80 - (_print_offset % 80)
        sub bx, dx

        ; Move the print offset to the next line
        ; _print_offset += 80 - (_print_offset % 80)
        mov ax, [_print_offset]
        add ax, bx
        mov word [_print_offset], ax

    .finished:
        popad
        ret

;
; Prints a byte as hex ("0x??")
; @input al - byte to print
;
kprint_byte:
    pushad
    
    ; Convert byte into hex chars
    call byte_to_hex

    ; Insert into template string
    mov byte [.template + 2], ah
    mov byte [.template + 3], al

    mov si, .template
    call kprint

    popad
    ret

    .template: db "0x??", 0

;
; Accepts an input byte and returns the char codes for it's individual nibbles
;
; @input al - byte to conver to hex
; @ouput al - first nibble (LS)
; @output ah - second nibble (MS)
;
byte_to_hex:
    push ebx

    ; Make a copy of the input byte
    mov ah, al
    
    ; Get least significant nibble in al
    and al, 0x0F

    ; Get most significant nibble in ah
    shr ah, 4

    ; Clear upper bits of ebx so we can use it as an offset into the table
    xor ebx, ebx

    ; Index into the table to get the first char code
    mov bl, al
    mov al, [.table + ebx]

    ; Index into the table to get the second char code
    mov bl, ah
    mov ah, [.table + ebx]

    pop ebx
    ret

    .table: db "0123456789ABCDEF"

;
; Function to clear the entire video buffer
;
clear_screen:
    pushad

    mov edi, 0

.clear_loop:
    ; Use di as an index into the video memory clearing 1 char (2 bytes) at a time
    mov word [edi * 2 + VIDEO_MEMORY_ADDR], 0x0000

    ; Increment the counter
    inc edi

    ; Check if we reached the end of the video memory
    cmp edi, SCREEN_CAPACITY
    jne .clear_loop

.clear_done:
    popad
    ret

;
; Scrolls the screen by one line
;
scroll_screen:
    pushad

    ; memcpy the last 24 rows up
    mov eax, 0
    lea eax, [VIDEO_MEMORY_ADDR + eax] ; dest

    mov ebx, SCREEN_COLS * 2
    lea ebx, [VIDEO_MEMORY_ADDR + ebx] ; src

    mov ecx, SCREEN_COLS * (SCREEN_ROWS - 1) * 2 ; num

    call memcpy

    ; memset the bottom row to 0
    mov eax, SCREEN_COLS * (SCREEN_ROWS - 1) * 2
    lea eax, [VIDEO_MEMORY_ADDR + eax] ; ptr

    mov bl, 0 ; value

    mov ecx, SCREEN_COLS * 2 ; num

    call memset

    popad
    ret

;
; Prints an error message and halts the processor
; @input esi - Pointer to the error message to print (null terminated)
;
__kpanic:
    ; Disable interrupts
    cli

    mov esi, .panic_msg
    call kprint

    ; Print the error message
    mov esi, eax
    call kprintln

    ; Print "    at "
    mov esi, .panic_at
    call kprint

    ; Print the file name
    mov esi, ebx
    call kprint

    ; Print ":"
    mov esi, .panic_colon
    call kprint

    ; Print the function name
    mov esi, ecx
    call kprint

    ; Print ":"
    mov esi, .panic_colon
    call kprint

    ; Print the line number
    mov esi, edx
    call kprintln

    ; Halt the processor
    .halt:
        hlt
        jmp .halt

    .panic_msg: db "KERNEL PANIC: ", 0
    .panic_at: db "    at ", 0
    .panic_colon: db ":", 0

%macro __kpanic_macro 4
    mov eax, %%panic_message
    mov ebx, %%file_name
    mov ecx, %%function_name
    mov edx, %%line_number
    call __kpanic

    %%function_name:
        db %1, 0

    %%panic_message:
        db %2, 0

    %%file_name:
        db %3, 0

    %%line_number:
        db %4, 0
%endmacro

%define kpanic(function_name, panic_message) \
    __kpanic_macro function_name, panic_message, __FILE__, %str(__LINE__)

%endif