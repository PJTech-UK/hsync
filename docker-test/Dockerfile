# Test image for hsync. Parametrised so the SAME harness can run the
# current Python 2.7 baseline and, later, the Python 3.12 port.
#
#   --build-arg PY_IMAGE=python:2.7.18-slim   (current baseline)
#   --build-arg PY_IMAGE=python:3.12-slim     (after the port)
ARG PY_IMAGE=python:2.7.18-slim
FROM ${PY_IMAGE}

WORKDIR /opt/hsync
COPY . /opt/hsync

# setup.py uses the legacy distutils `requires=` field (not install_requires),
# so pip installs only the hsync package + console script. urlgrabber (dead and
# unused) is NOT pulled. -e keeps it editable against the mounted source.
RUN pip install --no-cache-dir -e .

ENTRYPOINT []
