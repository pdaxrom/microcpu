org $0000

IFDEF CLI_FEATURE
    db $11
ELSE
    db $00
ENDIF

IFDEF CLI_VALUE
    IF CLI_VALUE
        db CLI_VALUE
    ELSE
        db $01
    ENDIF
ENDIF

IFDEF CLI_REMOVED
    skipped_removed_define_bad_opcode
ENDIF
