	cpu dcj-11
	org 0

	scc
	mov #012345, r0
	mov #02000, r1
	mov r0, (r1)
	mov (r1), r2
	mov r2, r0
	halt
