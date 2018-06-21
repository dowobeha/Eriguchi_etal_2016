all: run.tape run.tconf
	ducttape run.tape -C run.tconf

.PHONY: run
