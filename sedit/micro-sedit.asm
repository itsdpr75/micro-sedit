section .data
    hide_cursor db 0x1b, '[?25l', 0
    show_cursor db 0x1b, '[?25h', 0
    clear_screen db 0x1b, '[2J', 0x1b, '[H', 0
    clear_line db 0x1b, '[K', 0
    cursor_pos db 0x1b, '[00;00H', 0
    
    usage_msg db 'Uso: lsedit <archivo>', 0x0a, 0
    usage_len equ $ - usage_msg
    
    STDIN equ 0
    STDOUT equ 1
    STDERR equ 2
    SYS_READ equ 0
    SYS_WRITE equ 1
    SYS_OPEN equ 2
    SYS_CLOSE equ 3
    SYS_IOCTL equ 16
    SYS_EXIT equ 60
    TCGETS equ 0x5401
    TCSETS equ 0x5402
    TIOCGWINSZ equ 0x5413
    
    MAX_LINES equ 1000
    MAX_LINE_LEN equ 1000

section .bss
    lines resb MAX_LINES * MAX_LINE_LEN
    line_count resd 1
    cursor_x resd 1
    cursor_y resd 1
    offset_x resd 1
    offset_y resd 1
    rows resd 1
    cols resd 1
    filename resb 256
    orig_termios resb 60
    
    char_buf resb 1
    seq_buf resb 2
    num_buf resb 16
    win_size resb 8

section .text
    global _start

%macro syscall 4
    mov rax, %1
    mov rdi, %2
    mov rsi, %3
    mov rdx, %4
    syscall
%endmacro

_start:
    pop rcx
    cmp rcx, 2
    jne .usage
    
    pop rdi
    pop rdi
    mov rsi, filename
    call copy_string
    
    call enable_raw_mode
    call get_window_size
    call load_file
    
    mov dword [cursor_x], 0
    mov dword [cursor_y], 0
    mov dword [offset_x], 0
    mov dword [offset_y], 0
    
.main_loop:
    call adjust_scroll
    call refresh_screen
    
    syscall SYS_READ, STDIN, char_buf, 1
    cmp rax, 1
    jne .main_loop
    
    mov al, [char_buf]
    cmp al, 17
    je .quit
    cmp al, 19
    je .save
    cmp al, 27
    je .escape_seq
    cmp al, 127
    je .backspace
    cmp al, 13
    je .newline
    cmp al, 32
    jb .main_loop
    cmp al, 126
    ja .main_loop
    
    mov dil, al
    call insert_char
    jmp .main_loop

.escape_seq:
    syscall SYS_READ, STDIN, seq_buf, 2
    cmp rax, 2
    jne .main_loop
    
    cmp byte [seq_buf], '['
    jne .main_loop
    
    mov al, [seq_buf+1]
    cmp al, 'A'
    je .arrow_up
    cmp al, 'B'
    je .arrow_down
    cmp al, 'C'
    je .arrow_right
    cmp al, 'D'
    je .arrow_left
    jmp .main_loop

.arrow_up:
    cmp dword [cursor_y], 0
    je .main_loop
    dec dword [cursor_y]
    call adjust_cursor_x
    jmp .main_loop

.arrow_down:
    mov eax, [line_count]
    dec eax
    cmp [cursor_y], eax
    jge .main_loop
    inc dword [cursor_y]
    call adjust_cursor_x
    jmp .main_loop

.arrow_right:
    mov eax, [cursor_y]
    call get_line_length
    cmp [cursor_x], ecx
    jae .main_loop
    inc dword [cursor_x]
    jmp .main_loop

.arrow_left:
    cmp dword [cursor_x], 0
    je .main_loop
    dec dword [cursor_x]
    jmp .main_loop

.backspace:
    call delete_char
    jmp .main_loop

.newline:
    call new_line
    jmp .main_loop

.save:
    call save_file
    jmp .main_loop

.quit:
    call disable_raw_mode
    syscall SYS_EXIT, 0, 0, 0

.usage:
    syscall SYS_WRITE, STDERR, usage_msg, usage_len
    syscall SYS_EXIT, 1, 0, 0

enable_raw_mode:
    syscall SYS_IOCTL, STDIN, TCGETS, orig_termios

    mov rsi, orig_termios
    mov rdi, rsp
    mov rcx, 60
    rep movsb

    and dword [rsp], ~(0x2|0x100|0x10|0x20|0x200)  ; BRKINT|ICRNL|INPCK|ISTRIP|IXON
    and dword [rsp+4], ~1  ; OPOST
    or dword [rsp+8], 0x30  ; CS8
    and dword [rsp+12], ~(0x8|0x2|0x8000|0x1)  ; ECHO|ICANON|IEXTEN|ISIG
    
    mov byte [rsp+17+6], 0
    mov byte [rsp+17+5], 1
    
    syscall SYS_IOCTL, STDIN, TCSETS, rsp
    
    syscall SYS_WRITE, STDOUT, hide_cursor, 6
    ret

disable_raw_mode:
    syscall SYS_IOCTL, STDIN, TCSETS, orig_termios
    
    syscall SYS_WRITE, STDOUT, show_cursor, 6
    ret

get_window_size:
    syscall SYS_IOCTL, STDOUT, TIOCGWINSZ, win_size
    mov ax, [win_size]
    mov [cols], ax
    mov ax, [win_size+2]
    mov [rows], ax
    ret


; no esta terminado 
