# CargoMake by NeoSmart Technologies
# Written and maintained by Mahmoud Al-Qudsi <mqudsi@neosmart.net>
# Released under the MIT public license
# Obtain updates from https://github.com/neosmart/CargoMake

COLOR ?= always # Valid COLOR options: {always, auto, never}
CARGO = cargo --color $(COLOR) 
CARGO_OPTS = --manifest-path resin/Cargo.toml

.PHONY: all bench build check clean doc install publish run test update

all: build

build:
	@$(CARGO) build $(CARGO_OPTS) --release
	@mkdir -p priv/resin
	@cp resin/target/release/resin priv/resin/resind
	@cp resin/target/release/test_child priv/resin/test_child
	@cp resin/target/release/test_echo priv/resin/test_echo
	@cp resin/target/release/test_err priv/resin/test_err

clean:
	@$(CARGO) clean $(CARGO_OPTS)

test: build
	@$(CARGO) test $(CARGO_OPTS)

