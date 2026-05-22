org $0000

true_val equ 1
false_val equ 0
seen_symbol equ $12

IF true_val
    db 1
ELSE
    skipped_true_branch_bad_opcode
ENDIF

IF false_val
    skipped_false_branch_bad_opcode
ELSE
    db 2
ENDIF

IFDEF seen_symbol
    db 3
ELSE
    skipped_ifdef_bad_opcode
ENDIF

IFNDEF missing_symbol
    db 4
ELSE
    skipped_ifndef_bad_opcode
ENDIF

IF 1
    IF 0
        skipped_nested_bad_opcode
    ELSE
        db 5
    ENDIF
ENDIF

IF 0
    IF missing_forward + 1
        skipped_inactive_nested_bad_opcode
    ELSE
        skipped_inactive_else_bad_opcode
    ENDIF
ELSE
    db 6
ENDIF

label_defined:
IFDEF label_defined
    db 7
ENDIF

IFNDEF seen_symbol
    skipped_known_symbol_bad_opcode
ELSE
    db 8
ENDIF
