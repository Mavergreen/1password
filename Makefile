.PHONY: test pkg
test:
	bats tests/*.bats

pkg:
	sh packaging/macos/build_pkg.sh "$$(cat VERSION)" "mavericks-1password-$$(cat VERSION).pkg"
