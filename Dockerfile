# Base our tests on the tools image
FROM docker.io/ethcomsec/cellift:cellift-tools-main
COPY . /cellift-designs/cellift-ibex
WORKDIR /cellift-designs/cellift-ibex/cellift
CMD bash tests.sh
