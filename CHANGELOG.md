# Changelog

## [0.5.0](https://github.com/ZanardiZZ/garmin_coach_AI/compare/v0.4.0...v0.5.0) (2026-01-23)


### Features

* add ui smoke tests and installer updates ([58080be](https://github.com/ZanardiZZ/garmin_coach_AI/commit/58080bea4c9c84a49116283c2c554c71c5c02dcb))
* add upgrade mode to installer ([43d5cb7](https://github.com/ZanardiZZ/garmin_coach_AI/commit/43d5cb730884d11ff1f230b530be29bda22ffab6))


### Bug Fixes

* add Grafana apt repo on Debian ([b73d7cd](https://github.com/ZanardiZZ/garmin_coach_AI/commit/b73d7cdceaa6ac321ada00d089d850285d5dec9f))
* avoid interactive gpg prompt in installer ([93f0c31](https://github.com/ZanardiZZ/garmin_coach_AI/commit/93f0c316ac51fc32c3180ae0450cd5c2958b4373))
* make grafana install robust on Debian ([c308911](https://github.com/ZanardiZZ/garmin_coach_AI/commit/c30891178580eddf97c2374f6b62d6a285dda932))
* tolerate duplicate-column migrations ([94415b5](https://github.com/ZanardiZZ/garmin_coach_AI/commit/94415b548d635609005455b5f1b4bcd170be1188))

## [0.4.0](https://github.com/ZanardiZZ/garmin_coach_AI/compare/v0.3.0...v0.4.0) (2026-01-22)


### Features

* add coach chat and feedback across web and telegram ([dc3787c](https://github.com/ZanardiZZ/garmin_coach_AI/commit/dc3787c3c69205712be066a128290c8302d506fc))
* add mock coach chat and feedback ([f41ca4d](https://github.com/ZanardiZZ/garmin_coach_AI/commit/f41ca4d25fe4bf3956c7de30d1827af0bd37f5ca))
* add stats intent to telegram coach ([643e8cc](https://github.com/ZanardiZZ/garmin_coach_AI/commit/643e8cc563e80090c014481579aee953f66b7fc4))
* allow rescheduling workouts via coach ([b3a13b7](https://github.com/ZanardiZZ/garmin_coach_AI/commit/b3a13b72fbeb68aad1feec24cb9d85671f17a9d9))
* install Grafana dashboards without docker ([21b1a11](https://github.com/ZanardiZZ/garmin_coach_AI/commit/21b1a11081ce5f45dce1ec172c70c175748d3650))
* parse telegram intents for feedback and reschedule ([8a8406e](https://github.com/ZanardiZZ/garmin_coach_AI/commit/8a8406e04f7d316b78d243196cc72eacb5c53a42))
* precompute daily metrics for stats ([0f8784c](https://github.com/ZanardiZZ/garmin_coach_AI/commit/0f8784cb7c4f67007e730ba806c9ea67ca05aaa9))

## [0.3.0](https://github.com/ZanardiZZ/garmin_coach_AI/compare/v0.2.1...v0.3.0) (2026-01-22)


### Features

* add ActivityGPS mock data ([376d29b](https://github.com/ZanardiZZ/garmin_coach_AI/commit/376d29b14ef0a420d4114799b9f42f618b50ddc3))
* add mock seed data for dashboard ([6a24365](https://github.com/ZanardiZZ/garmin_coach_AI/commit/6a2436590c79f10dd0811a07fd70b12386df253d))


### Bug Fixes

* avoid BASH_SOURCE errors and npm/node conflicts ([4c2a2d7](https://github.com/ZanardiZZ/garmin_coach_AI/commit/4c2a2d7b4e1f74189fba1c3bbdb3d541a0249e64))
* handle BASH_SOURCE and npm install on Debian ([6fffc26](https://github.com/ZanardiZZ/garmin_coach_AI/commit/6fffc269f6bc6cbbc255ce27a042a4807f6904ae))
* handle piped installer path detection ([3e1b67e](https://github.com/ZanardiZZ/garmin_coach_AI/commit/3e1b67ec01c2d530459a0b8bdb790f8c10ad7475))
* harden installer for piped execution and npm deps ([508fe7f](https://github.com/ZanardiZZ/garmin_coach_AI/commit/508fe7f7a39433be0cd679155f07e4bc4e44176a))
* make installer quiet by default ([6d7c63a](https://github.com/ZanardiZZ/garmin_coach_AI/commit/6d7c63abf81fa51dc33d205804692f9ce3722892))

## [0.2.1](https://github.com/ZanardiZZ/garmin_coach_AI/compare/v0.2.0...v0.2.1) (2026-01-22)


### Bug Fixes

* release trigger ([fd47d7c](https://github.com/ZanardiZZ/garmin_coach_AI/commit/fd47d7c98d68e673895a990ef33309ea39e14c28))

## 0.2.0 - 2026-01-21
- Inicio da serie 0.2 com setup web, sync Garmin local e dashboard.
