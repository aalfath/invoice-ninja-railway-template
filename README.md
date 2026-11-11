# Invoice Ninja on Railway

Start script behind the Railway template for [Invoice Ninja](https://github.com/invoiceninja/invoiceninja) v5.

- Image: `invoiceninja/invoiceninja-debian:5.13.53@sha256:217a0f2d45403b9562f90af51762cdd22bc6d9728c9a8751571ff6bfefc51f64` (official, unmodified).
- `start.sh` runs as the service's start command. The template carries it inline as base64, so nothing is fetched from this repo at boot. It:
  1. Sets Railway-friendly defaults: production mode, `TRUSTED_PROXIES=*`, the database queue, file cache and sessions, the `snappdf` PDF renderer (the image's bundled Chrome) and mail to the log unless `MAIL_HOST` is set.
  2. Adds Caddy v2.11.9 as a web server on `PORT`. The release is checked against its published SHA-512 and cached on the storage volume. It runs under the image's own supervisord next to PHP-FPM, two queue workers and the scheduler. Upstream uses a separate nginx container with shared volumes, which Railway doesn't support.
  3. Waits for MySQL, then hands over to the image's `init.sh`. On first boot that migrates, seeds and creates the admin from `IN_USER_EMAIL` / `IN_PASSWORD`.
- `test.sh` runs the end-to-end check used before publishing: health, `/setup` closed, login, a client and an invoice, the invoice PDF, the client-portal link and its PDF download, and a document upload.

Rebuild the start command with: `sh -c 'echo <base64 of start.sh> | base64 -d > /tmp/railway-start.sh && exec sh /tmp/railway-start.sh'`
