# Changelog

The 0.1.0 entry was written by hand. Everything after it is generated from the
commits on `main`, which is why the voice changes partway down.

## [0.1.4](https://github.com/nparashar150/docket/compare/v0.1.3...v0.1.4) (2026-09-27)


### Features

* finish the Shortcut stub so a shortcut can be run from the shelf ([#133](https://github.com/nparashar150/docket/issues/133)) ([20db8cc](https://github.com/nparashar150/docket/commit/20db8ccf792751d9c551c31fc25b04427e70b31d))


### Bug Fixes

* stop describing a tile nobody can reach as what people will see ([#130](https://github.com/nparashar150/docket/issues/130)) ([5df5cca](https://github.com/nparashar150/docket/commit/5df5cca8c1a11280d62660b86ce7274fb48cb180))

## [0.1.3](https://github.com/nparashar150/docket/compare/v0.1.2...v0.1.3) (2026-09-27)


### Features

* give Calendar and Reminders the tiles their panels deserved ([95d5376](https://github.com/nparashar150/docket/commit/95d53765c91b6c522df9c06ccea93ea714e66236)), closes [#19](https://github.com/nparashar150/docket/issues/19)
* leave a handle on screen when the shelf hides ([#125](https://github.com/nparashar150/docket/issues/125)) ([c1537e1](https://github.com/nparashar150/docket/commit/c1537e19b92a8451d4af78fb113fb9f0adfe7d72)), closes [#3](https://github.com/nparashar150/docket/issues/3)
* let profiles be created, renamed, duplicated and deleted ([#117](https://github.com/nparashar150/docket/issues/117)) ([2aad9bb](https://github.com/nparashar150/docket/commit/2aad9bb4b1bf1e345cd0e32e4c515c79e4cb99a9)), closes [#29](https://github.com/nparashar150/docket/issues/29) [#36](https://github.com/nparashar150/docket/issues/36) [#31](https://github.com/nparashar150/docket/issues/31)
* let someone actually add a spacer ([#116](https://github.com/nparashar150/docket/issues/116)) ([f28ef08](https://github.com/nparashar150/docket/commit/f28ef084e667f277411966be677a87503eb64b5e)), closes [#33](https://github.com/nparashar150/docket/issues/33)
* make Back Up and Restore do something ([#115](https://github.com/nparashar150/docket/issues/115)) ([ebcedef](https://github.com/nparashar150/docket/commit/ebcedef0fd2c7b6bb828de2b4e21932849e350e6)), closes [#32](https://github.com/nparashar150/docket/issues/32)
* tell people when a new version exists ([#111](https://github.com/nparashar150/docket/issues/111)) ([c63b90c](https://github.com/nparashar150/docket/commit/c63b90c695a2ae46631a36b899606de416fe28ef)), closes [#110](https://github.com/nparashar150/docket/issues/110)
* yield the edge when Apple's Dock comes out ([#106](https://github.com/nparashar150/docket/issues/106)) ([4f1c4de](https://github.com/nparashar150/docket/commit/4f1c4de3015119d2ecbea2a1a78523beb4a67c24)), closes [#4](https://github.com/nparashar150/docket/issues/4)


### Bug Fixes

* actually receive the notification the Dock posts ([#105](https://github.com/nparashar150/docket/issues/105)) ([aa24465](https://github.com/nparashar150/docket/commit/aa2446534bc6d849d6b4ccef28d4ffed9cee3014)), closes [#12](https://github.com/nparashar150/docket/issues/12) [#37](https://github.com/nparashar150/docket/issues/37)
* connect the Focus Timer settings to the Focus Timer ([#127](https://github.com/nparashar150/docket/issues/127)) ([a410ed3](https://github.com/nparashar150/docket/commit/a410ed3806edf0d69cee13995a77dac6852cbf9e)), closes [#37](https://github.com/nparashar150/docket/issues/37)
* delete two stored settings nothing reads, and say why two others stay ([#126](https://github.com/nparashar150/docket/issues/126)) ([4e2333d](https://github.com/nparashar150/docket/commit/4e2333d8a0e3eaecba46004857950fcdd64957a1)), closes [#27](https://github.com/nparashar150/docket/issues/27) [#30](https://github.com/nparashar150/docket/issues/30)
* give each release its own build number ([#113](https://github.com/nparashar150/docket/issues/113)) ([a97bfbc](https://github.com/nparashar150/docket/commit/a97bfbcaf9c35c3475884704bb23a27c8ee95f69)), closes [#112](https://github.com/nparashar150/docket/issues/112)
* land on the tab that was asked for, and tell two widgets apart ([#123](https://github.com/nparashar150/docket/issues/123)) ([d15d346](https://github.com/nparashar150/docket/commit/d15d346292546c0f5444e6b15c824098bbe5c56b)), closes [#43](https://github.com/nparashar150/docket/issues/43) [#44](https://github.com/nparashar150/docket/issues/44)
* make a widget's options reachable and honest ([#107](https://github.com/nparashar150/docket/issues/107)) ([d1136fd](https://github.com/nparashar150/docket/commit/d1136fd6ced6c62f5accd7de1174daa12007efd5)), closes [#21](https://github.com/nparashar150/docket/issues/21) [#25](https://github.com/nparashar150/docket/issues/25) [#14](https://github.com/nparashar150/docket/issues/14)
* make the Dock tab apply what it is set to ([#109](https://github.com/nparashar150/docket/issues/109)) ([5c56ac9](https://github.com/nparashar150/docket/commit/5c56ac9b7ab320c0fc14d17fcb77970ba3a4269c)), closes [#6](https://github.com/nparashar150/docket/issues/6) [#5](https://github.com/nparashar150/docket/issues/5) [#7](https://github.com/nparashar150/docket/issues/7) [#8](https://github.com/nparashar150/docket/issues/8)
* make the menu bar and appearance settings apply ([#119](https://github.com/nparashar150/docket/issues/119)) ([dcded3a](https://github.com/nparashar150/docket/commit/dcded3aa1152965fff57668c35b2787b6925dc0b)), closes [#39](https://github.com/nparashar150/docket/issues/39) [#40](https://github.com/nparashar150/docket/issues/40) [#41](https://github.com/nparashar150/docket/issues/41)
* measure System Activity for what it actually draws ([#120](https://github.com/nparashar150/docket/issues/120)) ([422b12d](https://github.com/nparashar150/docket/commit/422b12de94ee409b6b4b336b6e18883c19a2336d)), closes [#22](https://github.com/nparashar150/docket/issues/22)
* reach the weather location, and make Hourly mean something on a side shelf ([#122](https://github.com/nparashar150/docket/issues/122)) ([ca287aa](https://github.com/nparashar150/docket/commit/ca287aadfe3176572f5ea0d2ac498382cf4a3978)), closes [#26](https://github.com/nparashar150/docket/issues/26) [#23](https://github.com/nparashar150/docket/issues/23)
* report a failed Dock apply where the button is, and verify something ([#118](https://github.com/nparashar150/docket/issues/118)) ([ae11597](https://github.com/nparashar150/docket/commit/ae11597f04312c7c34c2ce60041c5b9ece5707c0)), closes [#34](https://github.com/nparashar150/docket/issues/34) [#35](https://github.com/nparashar150/docket/issues/35)
* say why three library categories are empty ([#124](https://github.com/nparashar150/docket/issues/124)) ([4e625dd](https://github.com/nparashar150/docket/commit/4e625dd66cfb0f771ee960fbc52c20b3f46ef18f)), closes [#45](https://github.com/nparashar150/docket/issues/45)
* stop offering a chart to a layout that cannot draw one ([#121](https://github.com/nparashar150/docket/issues/121)) ([d1cc104](https://github.com/nparashar150/docket/commit/d1cc104a5068bf1707b7dbb1cbe92c5c199d7497)), closes [#20](https://github.com/nparashar150/docket/issues/20)
* stop offering options no widget reads ([#114](https://github.com/nparashar150/docket/issues/114)) ([6f63e1d](https://github.com/nparashar150/docket/commit/6f63e1d9787c1a6136e9ff2d035f295c53373f1c)), closes [#15](https://github.com/nparashar150/docket/issues/15) [#16](https://github.com/nparashar150/docket/issues/16) [#17](https://github.com/nparashar150/docket/issues/17) [#38](https://github.com/nparashar150/docket/issues/38)
* stop one unreadable value discarding the whole setup ([#108](https://github.com/nparashar150/docket/issues/108)) ([abe19b5](https://github.com/nparashar150/docket/commit/abe19b55abe9d8b3fb59591b4cc656faa47414ac)), closes [#13](https://github.com/nparashar150/docket/issues/13)

## [0.1.2](https://github.com/nparashar150/docket/compare/v0.1.1...v0.1.2) (2026-09-26)


### Features

* give the Show Trash toggle a Trash to show ([#100](https://github.com/nparashar150/docket/issues/100)) ([bfeb22b](https://github.com/nparashar150/docket/commit/bfeb22bef12ab976595cdbf87b72e56ba60f7a92)), closes [#1](https://github.com/nparashar150/docket/issues/1)


### Bug Fixes

* let the shelf go back to following the Dock ([#103](https://github.com/nparashar150/docket/issues/103)) ([7b096c7](https://github.com/nparashar150/docket/commit/7b096c71ba0575ce374eecb06054d96c004b01d4)), closes [#10](https://github.com/nparashar150/docket/issues/10) [#11](https://github.com/nparashar150/docket/issues/11) [#9](https://github.com/nparashar150/docket/issues/9)

## [0.1.1](https://github.com/nparashar150/docket/compare/v0.1.0...v0.1.1) (2026-09-26)


### Bug Fixes

* remove the app badges toggle, which was wired to nothing ([#98](https://github.com/nparashar150/docket/issues/98)) ([80ad1ed](https://github.com/nparashar150/docket/commit/80ad1edfcd8f642a57e0e6895cc3f18bc5c75742)), closes [#2](https://github.com/nparashar150/docket/issues/2)

## [0.1.0](https://github.com/nparashar150/docket/releases/tag/v0.1.0) (2026-09-26)

The first release. A shelf of live widgets, app groups and folders that sits
beside the macOS Dock, follows it when it moves, edge or size changes, and is
configured from the menu bar.

Unsigned and not notarised, so macOS 26 stops it the first time it is opened.
The release page says how to get past that.
