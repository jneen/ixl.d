DFLAGS =
DC = dmd

bin/%: src/%.d
	$(DC) $(DFLAGS) -of$@ -od./lib $<

lib/%.o: src/%.d
	$(DC) $(DFLAGS) -of$@ -od./lib $<

.PHONY: all
all: bin/ixl

CLEAN += bin/ixl **/*.o

.PHONY: test
TEST = tmp/test
test: $(TEST)

$(TEST): src/ixl.d
	@mkdir -p $(dir $(TEST))
	@touch $@
	$(DC) $(DFLAGS) -of$@ -unittest -run $< --test
	@echo tests passed.

.PHONY: clean
clean:
	rm -rf $(CLEAN)
