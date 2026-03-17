ARG NEXTCLOUD_VERSION=32
FROM nextcloud:${NEXTCLOUD_VERSION}-fpm

RUN apt-get update \
    && apt-get install -y --no-install-recommends smbclient libsmbclient-dev \
    && pecl install smbclient \
    && docker-php-ext-enable smbclient \
    && rm -rf /var/lib/apt/lists/*
