# Version History

## 0.2.5 - 2026-05-11

- Standardized CloudronManifest.json to BluePants conventions: switched `author` email and `contactEmail` from `admin@bluepants.dev` to `support@bluepants.dev`, moved `manifestVersion` to the top, reordered keys to canonical order, added `mediaLinks: []`.
- Confirmed adherence to original-app version scheme `N.N.N` (no packaging suffix).

## 0.2.0 - 2026-03-04

- Updated base image from `cloudron/base:4.2.0` to `cloudron/base:5.0.0`.
- Bumped app version to `0.2.0` in:
  - `CloudronManifest.json`
  - `app/version.txt`
  - `Dockerfile` image label (`org.opencontainers.image.version`)
- Added a new `0.2.0` release entry in `CloudronVersions.json`.

## 0.1.8

- Prior release.
