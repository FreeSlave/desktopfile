#!/bin/sh

set -ex

if [ "$USE_DOVERALLS" = "true" ]; then
    wget -q -O - "http://bit.ly/Doveralls" | bash
    dub test -b unittest-cov --compiler=${DC}
    rm ..-*
    ./doveralls
else
    dub test --compiler=${DC}
fi
