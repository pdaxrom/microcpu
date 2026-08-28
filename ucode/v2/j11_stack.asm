; DCJ11 User's Guide section 1.8: fixed kernel limit 0400 (hex 0100).
; Context 14: bit 0 yellow pending, 1 yellow inhibit, 2 vector stack push,
; 3 explicit PSW write, 4 pre-instruction trace, 5 red recovery in progress.
stack_check
	gset lr, 30
	set v3, $100
	bgeu stack_check_return, v2, v3
	gget v3, 14
	bmask_set stack_check_return, v3, 2
	bmask_set stack_check_yellow, v3, 4 ; trap frame always uses kernel stack
	gget v2, 8
	shr v2, v2, 14
	bmask_set stack_check_return, v2, 1 ; supervisor/user stacks aren't checked
stack_check_yellow
	or v3, v3, 1
	gset v3, 14
	gget v2, 23
	set v3, $0800
	or v2, v2, v3
	gset v2, 23
stack_check_return
	gget v2, 28
	gget v3, 27
	gget lr, 25
	gget pc, 30
