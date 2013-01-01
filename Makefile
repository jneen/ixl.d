%: %.d
	dmd -of$@ $<

%.test: %.d
	dmd -of$@ -unittest $<

.PHONY: test
test: tmp/tested

tmp/tested: ixl.test
	@mkdir -p tmp
	@touch $@
	./$<
	@echo tests passed.
