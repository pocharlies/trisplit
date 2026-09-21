.PHONY: build test clean

build:
	./build.sh

test:
	./tests/run.sh

clean:
	rm -rf TrisplitPanel.app
