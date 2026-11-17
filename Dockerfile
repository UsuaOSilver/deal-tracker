# syntax=docker/dockerfile:1

# Hardened build of changedetection.io from a pinned upstream commit.
# Differences from the upstream image: exact commit, hash-locked dependencies,
# non-root user, default OpenSSL security level, no runtime package installs.

ARG PYTHON_IMAGE=python:3.11-slim-bookworm@sha256:a83ba18aef0f865b1a4a611c2cf460fe446f2795673bbb9fe43be570439e3b39

FROM ${PYTHON_IMAGE} AS builder

# Upstream pin. Tag 0.70.3 plus one week of fixes. Change only after review,
# then run scripts/update-lock.sh.
ARG UPSTREAM_COMMIT=fdce08421c010b33f541a45dd89b5d10cebc124e
ADD --keep-git-dir=false https://github.com/dgtlmoon/changedetection.io.git#${UPSTREAM_COMMIT} /src

RUN pip install --no-cache-dir uv==0.9.30
ENV UV_LINK_MODE=copy \
    UV_COMPILE_BYTECODE=1 \
    UV_PYTHON=/usr/local/bin/python3

# Every package must match a hash in the lock file. Wheels only, except
# feedgen, which publishes no wheel and is built from its hashed sdist.
COPY requirements.lock /requirements.lock
RUN uv pip install \
      --require-hashes \
      --no-deps \
      --only-binary :all: \
      --no-binary feedgen \
      --target=/dependencies \
      -r /requirements.lock


FROM ${PYTHON_IMAGE}

RUN apt-get update && apt-get install -y --no-install-recommends \
      file \
      libxslt1.1 \
      locales \
      poppler-utils \
      zlib1g \
    && apt-get clean && rm -rf /var/lib/apt/lists/* \
    && sed -i 's/^# *en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen \
    && locale-gen

COPY --from=builder /dependencies /usr/local
ENV PYTHONPATH=/usr/local \
    PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    LC_ALL=en_US.UTF-8 \
    HOME=/tmp

COPY --from=builder /src/changedetectionio /app/changedetectionio
COPY --from=builder /src/docs/api-spec.yaml /app/docs/api-spec.yaml
COPY --from=builder /src/changedetection.py /app/changedetection.py

RUN pybabel compile -d /app/changedetectionio/translations \
    && python -m compileall -q /app \
    && groupadd --gid 10001 tracker \
    && useradd --uid 10001 --gid 10001 --no-create-home --shell /usr/sbin/nologin tracker \
    && mkdir /datastore \
    && chown 10001:10001 /datastore

USER 10001:10001
WORKDIR /app
EXPOSE 5000

# No entrypoint script: EXTRA_PACKAGES is ignored, nothing is installed at start.
CMD ["python", "./changedetection.py", "-d", "/datastore"]
