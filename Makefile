%: %.d
	dmd -of$@ $<

%.test: %.d
	dmd -of$@ -unittest $<

.PHONY: all
all: ixl

.PHONY: test
test: tmp/tested

tmp/tested: ixl.test
	@mkdir -p tmp
	@touch $@
	./$< --test
	@echo tests passed.
