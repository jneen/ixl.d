%: %.d
	dmd -of$@ $<

%.test: %.d
	dmd -of$@ -unittest $<

.PHONY: all
all: ixl

CLEAN += ixl *.o

TEST = tmp/tested

.PHONY: test
test: $(TEST)

CLEAN += $(TEST)

$(TEST): ixl.test
	@mkdir -p tmp
	@touch $@
	./$< --test
	@echo tests passed.

.PHONY: clean
clean:
	rm -rf $(CLEAN)
