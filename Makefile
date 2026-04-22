FLUTTER ?= flutter

.PHONY: bootstrap analyze test ci ios-build-check

bootstrap:
	$(FLUTTER) pub get

analyze:
	$(FLUTTER) analyze

test:
	$(FLUTTER) test

ci: bootstrap analyze test

ios-build-check:
	./build_check.sh
