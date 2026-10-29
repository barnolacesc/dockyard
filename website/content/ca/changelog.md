---
title: Changelog
layout: changelog
hideInstall: true
translationKey: changelog
---

## [0.2.7](https://github.com/barnolacesc/dockyard/releases/tag/v0.2.7) (2026-10-04)


### Features

* add icons and emojis for projects ([#255](https://github.com/barnolacesc/dockyard/issues/255)) ([3db01db](https://github.com/barnolacesc/dockyard/commit/3db01dbbbe1ad9c691d6bb64a853d71f688f9ce6))
* add persistent floating Global Terminal ([#259](https://github.com/barnolacesc/dockyard/issues/259)) ([9d63ddd](https://github.com/barnolacesc/dockyard/commit/9d63ddd376593e77ad03d99408a00e102f9c343e))
* **agent:** autofill issue contents when starting issue workstream ([#256](https://github.com/barnolacesc/dockyard/issues/256)) ([ce10e59](https://github.com/barnolacesc/dockyard/commit/ce10e59ebdfbfb5137c1b4e760842237a30aa116))
* **browser:** add agent-controlled Terminal Browser ([#254](https://github.com/barnolacesc/dockyard/issues/254)) ([4885906](https://github.com/barnolacesc/dockyard/commit/4885906c373cf0f930720b2548c04ef69945f18b))
* **sidebar:** auto-load scrollable GitHub issues and copy prompt on creation ([#249](https://github.com/barnolacesc/dockyard/issues/249)) ([d4ff128](https://github.com/barnolacesc/dockyard/commit/d4ff128d35fd70f05377917ba392a77273e46c8b))
* **ui:** improve workstream status lifecycle and active action tracking ([#258](https://github.com/barnolacesc/dockyard/issues/258)) ([7d1a3cf](https://github.com/barnolacesc/dockyard/commit/7d1a3cf967a577f502dca06dcf0a36f6961a5681))
* **ui:** refine workstream lifecycle states and fix warning pill contrast ([#251](https://github.com/barnolacesc/dockyard/issues/251)) ([840d582](https://github.com/barnolacesc/dockyard/commit/840d582cfadf576ff7bda137ee0c06f37163b390))


### Bug Fixes

* **agent:** scope agy session continuation to workspaces with existing conversations ([#252](https://github.com/barnolacesc/dockyard/issues/252)) ([801bd70](https://github.com/barnolacesc/dockyard/commit/801bd70ca337b5c5b68f126a7a855c2c2a7a33d3))

## [0.2.6](https://github.com/barnolacesc/dockyard/releases/tag/v0.2.6) (2026-09-21)


### Features

* add actionable agent attention notifications ([#213](https://github.com/barnolacesc/dockyard/issues/213)) ([91eec20](https://github.com/barnolacesc/dockyard/commit/91eec203d1118da30c9c86e1169a0e4ff24dee32))
* add Antigravity CLI (agy) support replacing legacy Gemini CLI ([#236](https://github.com/barnolacesc/dockyard/issues/236)) ([62c8b3d](https://github.com/barnolacesc/dockyard/commit/62c8b3dd1be8c8cd57f34429a24db0a725b348b1))
* add caffeinate mode ([#226](https://github.com/barnolacesc/dockyard/issues/226)) ([078c5da](https://github.com/barnolacesc/dockyard/commit/078c5dac52e6b905616886d423ab32df986edee2))
* add project root terminal ([#210](https://github.com/barnolacesc/dockyard/issues/210)) ([d12c7a5](https://github.com/barnolacesc/dockyard/commit/d12c7a5c8701c9cae7dc652ff9fd0c81a86bdf1f))
* **agent:** add Antigravity CLI (agy) lifecycle hooks and permission bypass ([#240](https://github.com/barnolacesc/dockyard/issues/240)) ([87fe408](https://github.com/barnolacesc/dockyard/commit/87fe408395c51d759a5e9e194be022945acb7b9a))
* **agent:** show active subagents in sidebar and workspace tab bar ([#247](https://github.com/barnolacesc/dockyard/issues/247)) ([6a9a9e8](https://github.com/barnolacesc/dockyard/commit/6a9a9e857a2da13dd372a43c59bfc7c93bea93f5))
* **attention:** add Dockyard work overview ([#221](https://github.com/barnolacesc/dockyard/issues/221)) ([36b9173](https://github.com/barnolacesc/dockyard/commit/36b917393f1504f5b5dade1688088cdd8c23514e))
* **browser:** persistent session and configurable link opening ([#244](https://github.com/barnolacesc/dockyard/issues/244)) ([830933b](https://github.com/barnolacesc/dockyard/commit/830933bccb6434782e26de79fc182d48d0256511))
* **caffeinate:** add sidebar toggle to cycle sleep modes ([#246](https://github.com/barnolacesc/dockyard/issues/246)) ([92ece1f](https://github.com/barnolacesc/dockyard/commit/92ece1f417d21b322bfc84d6eaab4790f0c0ecf4))
* configure workstreams from GitHub issues ([#220](https://github.com/barnolacesc/dockyard/issues/220)) ([8933bf2](https://github.com/barnolacesc/dockyard/commit/8933bf2a9ef7a237f7b73d0b7b0a4fc93323e1a6))
* **info:** improve worktree management and uncommitted changes handling ([#239](https://github.com/barnolacesc/dockyard/issues/239)) ([10c859e](https://github.com/barnolacesc/dockyard/commit/10c859e1da55fd2c53e6e9e6d5e0d71494da7ef0))
* **project:** add overview and terminal tabs with script configuration ([#238](https://github.com/barnolacesc/dockyard/issues/238)) ([263285e](https://github.com/barnolacesc/dockyard/commit/263285ea6c27fc7773a2546e6a267f0c57af8c11))
* rename Codex and OpenCode workstreams ([#217](https://github.com/barnolacesc/dockyard/issues/217)) ([9d27d0d](https://github.com/barnolacesc/dockyard/commit/9d27d0d6a22a94c92aeadced4ec192c419e942d3))
* show pull request CI checks ([#219](https://github.com/barnolacesc/dockyard/issues/219)) ([adf0196](https://github.com/barnolacesc/dockyard/commit/adf01960c5cb2728e5fe85aeed9192ec698dfe42))
* **sidebar:** report all PR statuses, merge conflicts, and CodeRabbit reviews ([#245](https://github.com/barnolacesc/dockyard/issues/245)) ([39fc5cc](https://github.com/barnolacesc/dockyard/commit/39fc5ccc2593d44150dae75de5ff287a294da200))
* **workspace:** collapse run script console and redesign workstream info layout ([#243](https://github.com/barnolacesc/dockyard/issues/243)) ([6e16046](https://github.com/barnolacesc/dockyard/commit/6e1604654ebf7b002e5a0499ebdf3034ce263ca6))
* **workspace:** redesign top bar with lifecycle pill and ai reviewer action ([#242](https://github.com/barnolacesc/dockyard/issues/242)) ([0d21219](https://github.com/barnolacesc/dockyard/commit/0d21219d7ddd25487cac7ae92c7efb79e7e7f8d5))
* **workstream:** toggle dangerous permissions in creation sheet ([#241](https://github.com/barnolacesc/dockyard/issues/241)) ([88e9883](https://github.com/barnolacesc/dockyard/commit/88e9883ba78a178f62e12b4b8214438c09f4d062))


### Bug Fixes

* **agent:** bound state cache reads ([#224](https://github.com/barnolacesc/dockyard/issues/224)) ([9a8d5c1](https://github.com/barnolacesc/dockyard/commit/9a8d5c151b8e9234750053b6abb3cfc4750e1b72))
* **attention:** show only current workspaces ([#216](https://github.com/barnolacesc/dockyard/issues/216)) ([6865dcc](https://github.com/barnolacesc/dockyard/commit/6865dcc9541c2d0440d1c729fb696092c7d589ff))
* **git:** bound repository exclude reads ([#234](https://github.com/barnolacesc/dockyard/issues/234)) ([67c5e05](https://github.com/barnolacesc/dockyard/commit/67c5e059802fc37b7b770614310057c56f634d7f))
* rename task tabs and branches separately ([#222](https://github.com/barnolacesc/dockyard/issues/222)) ([aef9b35](https://github.com/barnolacesc/dockyard/commit/aef9b350dce00b38f19cdc8ef268e07e899febb0))
* **settings:** bound CLI validation reads ([#232](https://github.com/barnolacesc/dockyard/issues/232)) ([69f2b88](https://github.com/barnolacesc/dockyard/commit/69f2b882a56fc8893e7d0a8e15e18e8b78b6e3bb))
* **setup:** bound output delivery backlog ([#230](https://github.com/barnolacesc/dockyard/issues/230)) ([2241ad3](https://github.com/barnolacesc/dockyard/commit/2241ad3feaf5be4fc11a0dd52ccb27bfa0403f69))
* **updater:** complete background source updates ([#227](https://github.com/barnolacesc/dockyard/issues/227)) ([e7c236c](https://github.com/barnolacesc/dockyard/commit/e7c236cf66e3d7d11d4985397715ce2b144098c8))
* **updater:** run source updates without terminal windows ([#215](https://github.com/barnolacesc/dockyard/issues/215)) ([34ecd1e](https://github.com/barnolacesc/dockyard/commit/34ecd1e0efb3eedb025bec1f02aa40bcffc79e6a))


### Refactoring

* **editor:** remove Monaco editor and use terminal editor for Cmd+O ([#237](https://github.com/barnolacesc/dockyard/issues/237)) ([9dc2d31](https://github.com/barnolacesc/dockyard/commit/9dc2d3105c8b2798419bed093a3b82ec25428a78))
* **localization:** support English and Catalan only ([#218](https://github.com/barnolacesc/dockyard/issues/218)) ([8bd5f85](https://github.com/barnolacesc/dockyard/commit/8bd5f85b2b072ae79bd92214ed893e98bca746c3))
* **sidebar:** remove recent workstreams section ([#248](https://github.com/barnolacesc/dockyard/issues/248)) ([fad6746](https://github.com/barnolacesc/dockyard/commit/fad6746cc836dced2ff5a99664ad87c0b27ea539))


### Documentation

* **roadmap:** reconcile post-weekend product priorities ([#235](https://github.com/barnolacesc/dockyard/issues/235)) ([3d45ea4](https://github.com/barnolacesc/dockyard/commit/3d45ea47badeada5b72c4dc79757489300870efb))
* specify agent attention notifications ([#211](https://github.com/barnolacesc/dockyard/issues/211)) ([60f0e2e](https://github.com/barnolacesc/dockyard/commit/60f0e2eee5c3db31769651cf352a576cd507368e))

## [0.2.5](https://github.com/barnolacesc/dockyard/releases/tag/v0.2.5) (2026-09-11)


### Features

* integrate remaining workstream and persistence changes ([#209](https://github.com/barnolacesc/dockyard/issues/209)) ([305323b](https://github.com/barnolacesc/dockyard/commit/305323b4ce8e110d08e570af7805a12d11b080c8))


### Bug Fixes

* **cache:** bound legacy migration enumeration ([#199](https://github.com/barnolacesc/dockyard/issues/199)) ([5450320](https://github.com/barnolacesc/dockyard/commit/54503203d9098a7231c08266f532350713954b48))
* **dev:** launch current debug build ([763e906](https://github.com/barnolacesc/dockyard/commit/763e90605df79acd609a171a2b0ff4de99b4a8b4))
* **persistence:** bound project snapshot decoding ([#201](https://github.com/barnolacesc/dockyard/issues/201)) ([9215bf5](https://github.com/barnolacesc/dockyard/commit/9215bf5a6e764ca608fa7c16e75baf379dc77e58))
* **terminal:** support macOS dictation ([af3fef5](https://github.com/barnolacesc/dockyard/commit/af3fef5c1faac6e46b9ba60fb4abe93db97ba1b3))
* **terminal:** support macOS dictation ([e24314c](https://github.com/barnolacesc/dockyard/commit/e24314c941112fb5348983b6fe7df98105414722))
* **workspace:** make blocking notices passive ([#208](https://github.com/barnolacesc/dockyard/issues/208)) ([9edbb7f](https://github.com/barnolacesc/dockyard/commit/9edbb7fc5d1cfd227813f73d35cd8064283c1ed6))

## [0.2.4](https://github.com/barnolacesc/dockyard/releases/tag/v0.2.4) (2026-09-08)


### Features

* **sidebar:** add persistent project colors ([bbd4a54](https://github.com/barnolacesc/dockyard/commit/bbd4a5430df7785cb0c8cb1e4959eabbc46a5562))
* **sidebar:** add persistent project colors ([35e78f6](https://github.com/barnolacesc/dockyard/commit/35e78f69d0c7623a0dbefd7c8324324e0df7d740))


### Bug Fixes

* **updater:** detect stale running builds ([f2a5a00](https://github.com/barnolacesc/dockyard/commit/f2a5a0074f8d2aa2570e29c5669a4669f7e2cb7c))
* **updater:** detect stale running builds ([cdcc6ae](https://github.com/barnolacesc/dockyard/commit/cdcc6aea4ecb9b89ec85e061bb1f9f645fa9958b))

## [0.2.3](https://github.com/barnolacesc/dockyard/releases/tag/v0.2.3) (2026-09-08)


### Features

* **ui:** add agent attention workspace ([dfb1ef0](https://github.com/barnolacesc/dockyard/commit/dfb1ef0c716ad045cf4e515ceaf041ba3065a24a))
* **ui:** add agent attention workspace ([bc3f0cd](https://github.com/barnolacesc/dockyard/commit/bc3f0cdae0368180af39928ee2f6531caec6c4d3))


### Bug Fixes

* **ui:** tighten sidebar row spacing ([8691129](https://github.com/barnolacesc/dockyard/commit/869112909da629f1291b68b4c3afac82af716896))
* **ui:** tighten sidebar row spacing ([ccec6d7](https://github.com/barnolacesc/dockyard/commit/ccec6d7fdc75d8532efc796122095dc5c39843c0))

## [0.2.2](https://github.com/barnolacesc/dockyard/releases/tag/v0.2.2) (2026-09-08)


### Features

* add getting-started tour flow content ([982523b](https://github.com/barnolacesc/dockyard/commit/982523bc8112c2548a78cc2466d8bee3da3724a5))
* add interactive getting-started tour and what's new panel ([c300666](https://github.com/barnolacesc/dockyard/commit/c300666af4bf20edc4bb1b34ce9b34924cb30462))
* add tour data model and anchor plumbing ([6fbfe8d](https://github.com/barnolacesc/dockyard/commit/6fbfe8d2acabd3e336cafd8193ef6272524e716b))
* add tour entry points in Help menu and onboarding ([52f3619](https://github.com/barnolacesc/dockyard/commit/52f36198109bc73d74379d78b30d049d839be106))
* add tour overlay, anchors, and run/config event posts ([daff1b8](https://github.com/barnolacesc/dockyard/commit/daff1b84d0335fe71e2c16d241fa7bc8edf7c917))
* add TourController with notification-driven advancement ([22b405e](https://github.com/barnolacesc/dockyard/commit/22b405e8af44e39b4187e97b843395bec94d6468))
* add what's new gate, models, and catalog ([bad3ba9](https://github.com/barnolacesc/dockyard/commit/bad3ba96eaead1ada0c1f413cbc47eb9abf38cba))
* add what's new panel with per-version gate ([2ec9119](https://github.com/barnolacesc/dockyard/commit/2ec9119ec8dd45bbc48fde5d5fdd0ab03bc17a8f))
* **agent:** aggregate Claude subagent status ([cd99804](https://github.com/barnolacesc/dockyard/commit/cd99804ecaa0805f6bccfdb64ff21c7c8020deed))
* **agent:** define capability contract ([136ebe1](https://github.com/barnolacesc/dockyard/commit/136ebe128b94c6910379bd1008ac6adef5b1c43a))
* **agent:** define capability contract ([cb35e3d](https://github.com/barnolacesc/dockyard/commit/cb35e3d521d539eb3f43db6615268a8a6b4a2bce))
* **github:** add issue task preview model ([56a5e63](https://github.com/barnolacesc/dockyard/commit/56a5e63fa5db0aef5726778ccf13dc13b89c03a4))
* name agent sessions after the task branch ([840b9b4](https://github.com/barnolacesc/dockyard/commit/840b9b42e3da19d7aa535eecdae114c4d8a4bd41))
* name Claude Code agent sessions after the task branch ([7e72699](https://github.com/barnolacesc/dockyard/commit/7e72699bbc7551f1956b27009b121647ae50e551))
* show Claude in Chrome activity ([aabce5f](https://github.com/barnolacesc/dockyard/commit/aabce5f62ea4db204d1d02be4b3054b4a805ffe9))
* show Claude in Chrome activity ([bf0d04f](https://github.com/barnolacesc/dockyard/commit/bf0d04fa1f7ba7f3a433cfa3b89152db4d27fff4))
* **tour:** add passive power features showcase ([6bcc263](https://github.com/barnolacesc/dockyard/commit/6bcc2637580298642491cd58294151472b009b45))
* **tour:** add workspace tabs showcase ([35f280c](https://github.com/barnolacesc/dockyard/commit/35f280c4d20167f8605ce0379c266e062aaab78a))
* triage worktree list, delete branches on prune, fix stale overview ([6a8c87c](https://github.com/barnolacesc/dockyard/commit/6a8c87c3a41b8b6d5c502d9495db1225d3b4fd2b))
* **worktrees:** classify merged pull requests ([644d5da](https://github.com/barnolacesc/dockyard/commit/644d5da7367abacc2491ef47798518b2a10621d9))
* **worktrees:** classify merged pull requests ([bd5f8e5](https://github.com/barnolacesc/dockyard/commit/bd5f8e59f43224ead0961b0cd119c1e86e7f442c))


### Bug Fixes

* **actions:** bound PR mutation output ([d3595ef](https://github.com/barnolacesc/dockyard/commit/d3595ef215dc95c6e4b51a62dccf408d45e1930b))
* **actions:** bound push output ([af15566](https://github.com/barnolacesc/dockyard/commit/af1556673719e7f64e84fce91a2eb1e0cca7168d))
* **actions:** terminate cancelled PR mutations ([6753ae2](https://github.com/barnolacesc/dockyard/commit/6753ae25ddd36a1eba53abebcfa04c667a573eab))
* **actions:** terminate cancelled PR mutations ([8d87ab8](https://github.com/barnolacesc/dockyard/commit/8d87ab86bd9ea0dc07360206d9838731e75b2370))
* **browser:** bound state cache reads ([bfbfc9c](https://github.com/barnolacesc/dockyard/commit/bfbfc9ca28c21dfeaba48e2e83d372b8f75b4121))
* **browser:** bound state cache reads ([390f19b](https://github.com/barnolacesc/dockyard/commit/390f19b9412886c26393bef2cb1eee5f79eecb0e))
* **browser:** secure browser-state cache files ([440279c](https://github.com/barnolacesc/dockyard/commit/440279cf87bad71cd5396c2a5a896503f139a2bd))
* **config:** bound script configuration reads ([ed53f28](https://github.com/barnolacesc/dockyard/commit/ed53f28a2a2879ab1329d595c6f869d64b6cb9e2))
* **docs:** bound workstream preview reads ([459568d](https://github.com/barnolacesc/dockyard/commit/459568df3c297333b48aac18d2a53dabee49c7fb))
* **docs:** contain standard document reads ([d66ecb7](https://github.com/barnolacesc/dockyard/commit/d66ecb7ad3af685720356ef395cd56f825cd00b0))
* don't let untracked files block self-update rebase ([ecabe78](https://github.com/barnolacesc/dockyard/commit/ecabe78ee1ed8360fa7aec0ac53b5ad5b525daec))
* **editor:** bound Monaco resource responses ([bc89e4e](https://github.com/barnolacesc/dockyard/commit/bc89e4e989b488252cedb0723afb75c39b621529))
* **editor:** bound source-file reads ([37f5e0a](https://github.com/barnolacesc/dockyard/commit/37f5e0ac4944667969ba4e1cab1c09d382a6b92d))
* **editor:** contain close-tab saves ([ed95589](https://github.com/barnolacesc/dockyard/commit/ed955896ee1074ba10e1e4274308ad440ee9b779))
* **editor:** contain close-tab saves ([eef5f89](https://github.com/barnolacesc/dockyard/commit/eef5f898ac1084453608f32b2e1d7afd424a44a4))
* **editor:** contain Monaco resource paths ([05e3700](https://github.com/barnolacesc/dockyard/commit/05e37005c4f430ab2ed8b8a6f6649fbec8281824))
* **editor:** contain workspace file access ([8588a40](https://github.com/barnolacesc/dockyard/commit/8588a404efd62acf6add4dac27c74d6d9a7a2fe9))
* **environment:** bound description metadata reads ([e9bf004](https://github.com/barnolacesc/dockyard/commit/e9bf004524f57ad83761157e4a4783e079b8210f))
* **environment:** contain automatic activation paths ([7c78ec2](https://github.com/barnolacesc/dockyard/commit/7c78ec27a29b1b7668d2d16c00bb45c2e2a1cfa2))
* **environment:** contain automatic activation paths ([c3bb23a](https://github.com/barnolacesc/dockyard/commit/c3bb23aa85691d33e1c726fbd88fc9aa6f1da574))
* force worktree removal in prune to handle populated submodules ([0dbcd7e](https://github.com/barnolacesc/dockyard/commit/0dbcd7e5a3d49fa15dcaba6ee4ef96183c5e29ee))
* **github:** bound read-only metadata probes ([96e331e](https://github.com/barnolacesc/dockyard/commit/96e331e484a7ce21f08e03ffe812e691b39da771))
* **github:** preserve Unicode issue text ([6561d28](https://github.com/barnolacesc/dockyard/commit/6561d2887ec5acb83b898610926451a20d014550))
* **git:** preserve dirty default checkout ([fce9d0f](https://github.com/barnolacesc/dockyard/commit/fce9d0f61ee8b673ea1f09f27cb82e7d0245b5fb))
* **git:** preserve dirty default checkout ([de12c16](https://github.com/barnolacesc/dockyard/commit/de12c168a33df5d5e4e28d6b20f581099a08d8b4))
* **logging:** bound unified-log polling snapshots ([78fd3f3](https://github.com/barnolacesc/dockyard/commit/78fd3f37e63b3cfdb65bc1720f2a61150bb5e715))
* **logging:** cap detailed launch log growth ([f8848ce](https://github.com/barnolacesc/dockyard/commit/f8848cea46f494c69dc51a5accd38eb4bf1bbb5a))
* **logging:** secure detailed launch logs ([8b31afc](https://github.com/barnolacesc/dockyard/commit/8b31afc19b0012f57df5d695be33d092298b3352))
* **opencode:** account for debug tmux session name ([ac3e684](https://github.com/barnolacesc/dockyard/commit/ac3e684acbcc340ac7932d78b741c0d387eb3688))
* **opencode:** define supported agent capabilities ([9ec32a3](https://github.com/barnolacesc/dockyard/commit/9ec32a3fa986e849cb50d9b8659db0d40dcdf1df))
* **opencode:** define supported agent capabilities ([6532089](https://github.com/barnolacesc/dockyard/commit/6532089230fe852a03f8005010201b890d513d8e))
* **paths:** respect home directory boundary ([d386331](https://github.com/barnolacesc/dockyard/commit/d3863310954a0d58007e78a8f2a5f17a8270cc49))
* **persistence:** enforce private state directories ([05e2a67](https://github.com/barnolacesc/dockyard/commit/05e2a679e045e19fd4f99c5734b5777edfdff801))
* **persistence:** isolate malformed project records ([fe3a7df](https://github.com/barnolacesc/dockyard/commit/fe3a7dfb23af02d71789ea62ba6fa3243c8d234e))
* **persistence:** isolate malformed project records ([51db415](https://github.com/barnolacesc/dockyard/commit/51db41588730f27142672e8c114719b8e68669b3))
* **persistence:** isolate malformed tab snapshots ([12af455](https://github.com/barnolacesc/dockyard/commit/12af45583ed9608ff42a0588850a99c05bee21a4))
* **persistence:** preserve cache migration destinations ([92ffc91](https://github.com/barnolacesc/dockyard/commit/92ffc913a22753ee1be933621096e9d1bc25eef2))
* **persistence:** preserve cache migration destinations ([1d0d9ef](https://github.com/barnolacesc/dockyard/commit/1d0d9efeee22f0b50da75a356c8bdd4b52dcb8a8))
* **persistence:** preserve valid setup completion state ([b34d5cd](https://github.com/barnolacesc/dockyard/commit/b34d5cd73746f6e1da86b62b849f614b01721c76))
* **persistence:** protect watcher state directories ([6b07927](https://github.com/barnolacesc/dockyard/commit/6b0792766c31a0deea85a15a4eb4eb01e4e9ff72))
* **persistence:** protect watcher state directories ([cd2874b](https://github.com/barnolacesc/dockyard/commit/cd2874bd5c771c778540da1091541670e08314f2))
* **persistence:** recover agent state watcher ([9444fe9](https://github.com/barnolacesc/dockyard/commit/9444fe97489a150fabeea55a22fc39e2714646e2))
* **persistence:** recover valid setup completion state ([a23633e](https://github.com/barnolacesc/dockyard/commit/a23633e623fc25a0809310985aa8c3be16f2bd92))
* **persistence:** recover worktree HEAD watchers ([1a26277](https://github.com/barnolacesc/dockyard/commit/1a262772fa0afd8f2fbedb6857e5b5ee0eee183a))
* **port-detection:** bound run-state cache reads ([08ec8b3](https://github.com/barnolacesc/dockyard/commit/08ec8b33781b5ea406a1dcf5eeaa071954c1ebd6))
* **port-detection:** bound run-state cache reads ([e389ea0](https://github.com/barnolacesc/dockyard/commit/e389ea03a78bbf9aaf216975f6c5edecceebdc43))
* **port-detection:** contain env port inference ([d75b996](https://github.com/barnolacesc/dockyard/commit/d75b9960a93b54e8529c83a969f173517af64b5e))
* **port-detection:** recover replaced state watcher ([97f62a7](https://github.com/barnolacesc/dockyard/commit/97f62a7a7ac37f5b8f52223d6f05cb15f0f61085))
* re-exec latest self-update script so update-flow fixes apply immediately ([33b3fdb](https://github.com/barnolacesc/dockyard/commit/33b3fdb6c227d8b633f3163e22aba93046046d84))
* re-exec latest self-update script so update-flow fixes apply immediately ([558dc75](https://github.com/barnolacesc/dockyard/commit/558dc758cc5fd215906eacdf37cc0f478cf0ff91))
* **run-state:** reject stale process snapshots ([ee6675a](https://github.com/barnolacesc/dockyard/commit/ee6675ad9779f0d80c8800c06243d98748046f2a))
* **run-state:** reject stale process snapshots ([2a6014e](https://github.com/barnolacesc/dockyard/commit/2a6014efea9a64c5ce5deab5e72e96633092d65e))
* scope tour run-start signal and harden controller ([d153e26](https://github.com/barnolacesc/dockyard/commit/d153e26099062e928101b1f680a6bb9001eface5))
* **scripts:** contain project config resolution ([b4a4405](https://github.com/barnolacesc/dockyard/commit/b4a4405f2d15e1c3d7c980c0c545dfdabb85f907))
* **setup:** drain output before completion ([4868c8a](https://github.com/barnolacesc/dockyard/commit/4868c8af95ba9a643c7ae7726e0cccf223d73cc8))
* **sidebar:** preserve selected workstream contrast ([2f8c244](https://github.com/barnolacesc/dockyard/commit/2f8c2440e0a91b04ba67bb556998a0d1501b805e))
* **sidebar:** preserve selected workstream contrast ([a76f42e](https://github.com/barnolacesc/dockyard/commit/a76f42e8908170700adcf20bde0eb80ee8194409))
* **stack-detection:** contain metadata reads ([6042b61](https://github.com/barnolacesc/dockyard/commit/6042b61a24a074eddf48ba5ecf692629b8cf6178))
* **stack:** bound manifest inspection reads ([ab35250](https://github.com/barnolacesc/dockyard/commit/ab352503d556dc59612b9cf9a5edc7392987d0bc))
* **tests:** pass workstreamID in PortDetectorWatcherTests snapshots ([5961a70](https://github.com/barnolacesc/dockyard/commit/5961a70a17dccac1dd2446ef37c4eeef5300ea95))
* **tmux:** bound cached configuration reads ([f4ed23a](https://github.com/barnolacesc/dockyard/commit/f4ed23a23899f20baf6bd7b5c709f86ef616c03b))
* **tmux:** preserve sessions across app restarts ([4bf0150](https://github.com/barnolacesc/dockyard/commit/4bf0150146c0ffb66e81b9c56c53271682e7a245))
* **tmux:** protect diagnostic cache permissions ([49ff869](https://github.com/barnolacesc/dockyard/commit/49ff869ac4f4b17ec2becf36c94ef95ba084b1ed))
* **tmux:** protect diagnostic cache permissions ([12200ab](https://github.com/barnolacesc/dockyard/commit/12200ab1222b5130743c8a0f9476399dd449d738))
* **tmux:** restore session persistence across app restarts ([99b68df](https://github.com/barnolacesc/dockyard/commit/99b68dfb91afbb80c2a48f0c20b3f0aa3cfd4f9e))
* **tools:** bound login shell path discovery ([8ac3c40](https://github.com/barnolacesc/dockyard/commit/8ac3c40e77f4c67322216202781ef53429ec5233))
* **tools:** bound startup detection probes ([e0f4ec1](https://github.com/barnolacesc/dockyard/commit/e0f4ec1b2bd8dc30f8623a3f5d2ed8071c39f31c))
* **updater:** bound update-check output ([321613f](https://github.com/barnolacesc/dockyard/commit/321613f558384926d203f969048c97ede1a3a91b))
* **usage:** bound Claude transcript parsing ([addd262](https://github.com/barnolacesc/dockyard/commit/addd26209301b0def3a4e8cf8e9044e7de5b34e4))
* **usage:** bound Claude usage probe ([7f7fd40](https://github.com/barnolacesc/dockyard/commit/7f7fd40958dd308008d4de8795347d94719fe6ec))
* **usage:** bound Codex probe IO ([9bdc542](https://github.com/barnolacesc/dockyard/commit/9bdc5422fc5cf30cf6550eb2d7888200115b1b2f))
* worktree triage, prune branches + submodule force-remove, self-update untracked files ([95217cd](https://github.com/barnolacesc/dockyard/commit/95217cd929b757b589acf2e6f1753a719a49dde8))
* **worktree:** bound gitfile indirection reads ([83d6965](https://github.com/barnolacesc/dockyard/commit/83d69653a1d256c197081f0b3aae6b7f42ed93da))
* **worktree:** refuse unregistered purge targets ([d465b3e](https://github.com/barnolacesc/dockyard/commit/d465b3e14803770dd4eb1c2b8195a2e5256acf56))
* **worktree:** refuse unregistered purge targets ([da5d734](https://github.com/barnolacesc/dockyard/commit/da5d734251076d413cdddaaf7100017a16af401e))


### Miscellaneous

* integrate audited open pull requests ([28422ea](https://github.com/barnolacesc/dockyard/commit/28422ea5fa46bb7c9465d91c354e3417da9a0887))
* merge main and resolve localization conflicts ([a2c8e35](https://github.com/barnolacesc/dockyard/commit/a2c8e352eece12e5db106f6a44b9389f764fbf70))
* merge reviewed openclaw PRs [#79](https://github.com/barnolacesc/dockyard/issues/79)–[#107](https://github.com/barnolacesc/dockyard/issues/107) ([2a92c7e](https://github.com/barnolacesc/dockyard/commit/2a92c7ebb8963f991bceecfd431d22be162c2c04))
* remove Barcelona motto from website footer and unused app strings ([1ade116](https://github.com/barnolacesc/dockyard/commit/1ade11615dba082063eb9e5029a3054a105abd29))


### Documentation

* lead README with install/usage, remove Barcelona motto ([ceeea08](https://github.com/barnolacesc/dockyard/commit/ceeea0811d385396f497632469a705b184a13953))
* note release-please CI approval quirk in TODO ([393d162](https://github.com/barnolacesc/dockyard/commit/393d1625640bf8af476aad73331d0d2f7d0bea17))
* note release-please CI approval quirk in TODO ([1c1c4b2](https://github.com/barnolacesc/dockyard/commit/1c1c4b26db9a980b9cdf1aa600ebcb3da0a9af7d))
* **readme:** consolidate install instructions at top, drop motto footer ([05ef2e5](https://github.com/barnolacesc/dockyard/commit/05ef2e520f038bf138ecba7e698e717facf99d1c))
* **roadmap:** add Herdr runtime direction ([a82965f](https://github.com/barnolacesc/dockyard/commit/a82965f87456db782fef3fe833e25fedbf9d5b29))
* **roadmap:** align Dockyard with Orca insights ([eca59d8](https://github.com/barnolacesc/dockyard/commit/eca59d8f2b099d54f44e076bbafa66f5b8dc2563))
* **roadmap:** clarify tmux regression scope ([18227f7](https://github.com/barnolacesc/dockyard/commit/18227f7361365c9ea0fc5b8b615c0ee218940076))
* **roadmap:** link bounded gitfile review ([14a6b77](https://github.com/barnolacesc/dockyard/commit/14a6b7731850e9aa1ac73648d566f09b047165f4))
* **roadmap:** link browser state review ([df351b9](https://github.com/barnolacesc/dockyard/commit/df351b93038fe9a9e0874ef5ae44b2a9ed64d8bb))
* **roadmap:** link cache migration review ([02e0be9](https://github.com/barnolacesc/dockyard/commit/02e0be9aa55ce527e8bfc3fc5ca1c03b53e3075f))
* **roadmap:** link Codex probe review ([67c9783](https://github.com/barnolacesc/dockyard/commit/67c9783efba2b5138bf136e56c10499c090403a3))
* **roadmap:** link description metadata review ([250457c](https://github.com/barnolacesc/dockyard/commit/250457cef49a8a71ab325f95f3ba629f64f27338))
* **roadmap:** link editor read hardening ([3e6db69](https://github.com/barnolacesc/dockyard/commit/3e6db6995c949e663aed18e8b964a5a6bddb257b))
* **roadmap:** link helper verification review ([a6f318c](https://github.com/barnolacesc/dockyard/commit/a6f318cf7c7be8b486fdc21de1fadde370a1db93))
* **roadmap:** link issue preview review ([ed98b44](https://github.com/barnolacesc/dockyard/commit/ed98b44c62f717482cfc0dc41f0a811a940863a3))
* **roadmap:** link launch log retention review ([6a5d8cb](https://github.com/barnolacesc/dockyard/commit/6a5d8cb5edf1144e01e231793f0586a42fcd605e))
* **roadmap:** link login shell probe review ([e25f2d2](https://github.com/barnolacesc/dockyard/commit/e25f2d2ed4b39c600570e027d9df0fa140419b11))
* **roadmap:** link merged PR classification review ([a80a496](https://github.com/barnolacesc/dockyard/commit/a80a496e97f918bdd9bff615f17b382ea2e6554c))
* **roadmap:** link Monaco resource review ([1b7da71](https://github.com/barnolacesc/dockyard/commit/1b7da71c83b30bb5999666a2de7e6aeb42b1cad2))
* **roadmap:** link power features review ([dc4f5f9](https://github.com/barnolacesc/dockyard/commit/dc4f5f9e3736842250547ed271f22e04c3622cd9))
* **roadmap:** link push output review ([874848a](https://github.com/barnolacesc/dockyard/commit/874848a95918f36ccfb87da02c15d23cb52e5890))
* **roadmap:** link R47 review ([3a4031a](https://github.com/barnolacesc/dockyard/commit/3a4031ad1ab62bf8aacc47c77bb196b55d154d45))
* **roadmap:** link R56 review ([87092c3](https://github.com/barnolacesc/dockyard/commit/87092c3f9c5d01a47ccc9148565baab64eba2685))
* **roadmap:** link R58 review ([4aa4817](https://github.com/barnolacesc/dockyard/commit/4aa4817edb251e34c5f99c40407c64b8ee30ad1e))
* **roadmap:** link run-state review ([d18bd04](https://github.com/barnolacesc/dockyard/commit/d18bd04a368fa700de9a8c273aaebf563299c90b))
* **roadmap:** link run-state validation PR ([4dd7d8f](https://github.com/barnolacesc/dockyard/commit/4dd7d8f6e20550fc160137d3d21828892b9abc34))
* **roadmap:** link subagent status review ([569bd4c](https://github.com/barnolacesc/dockyard/commit/569bd4c81d092567d030c24b4219f483561453df))
* **roadmap:** link unified-log snapshot review ([f62a46e](https://github.com/barnolacesc/dockyard/commit/f62a46e0154dd2ec2d563efe0d2d87b54495627b))
* **roadmap:** link workspace tabs tour review ([3ee77a4](https://github.com/barnolacesc/dockyard/commit/3ee77a48327b12f4676b1f127bbd87f3bfc7c575))
* **roadmap:** link worktree purge review ([7666469](https://github.com/barnolacesc/dockyard/commit/7666469113a2df6bc86c556698d074238971571c))
* **roadmap:** mark browser state CI green ([94e05bc](https://github.com/barnolacesc/dockyard/commit/94e05bc2164d622bf0087c3de6ad0ac5e8c40bbd))
* **roadmap:** reconcile document containment work ([ce57b45](https://github.com/barnolacesc/dockyard/commit/ce57b45f0e603ef39b2f483e4eb03751b2d8da7c))
* **roadmap:** reconcile tmux PR blocker ([07b94a8](https://github.com/barnolacesc/dockyard/commit/07b94a88c96d4fbccc591ef4c4910f1846f2bbb5))
* **roadmap:** record agent watcher recovery PR ([db2bedc](https://github.com/barnolacesc/dockyard/commit/db2bedcf922f194170cb8b04be86c7023b758ce5))
* **roadmap:** record bounded GitHub probes ([f6598dc](https://github.com/barnolacesc/dockyard/commit/f6598dcbefb7fa3af7643a8d0e3b1578670afbeb))
* **roadmap:** record bounded tool probes ([604c3aa](https://github.com/barnolacesc/dockyard/commit/604c3aa37e2bb4b8f72bf41efe17332b0f649368))
* **roadmap:** record browser state CI ([63d1c15](https://github.com/barnolacesc/dockyard/commit/63d1c153ecd1633642feec3178cc8967f548711e))
* **roadmap:** record browser state CI ([4b127a9](https://github.com/barnolacesc/dockyard/commit/4b127a90f56f3141b95b76669dc5418c046aebb2))
* **roadmap:** record browser state PR ([b4d1e11](https://github.com/barnolacesc/dockyard/commit/b4d1e11f9fa299ac7dd8068207da1692280392ac))
* **roadmap:** record cache migration CI evidence ([0cee878](https://github.com/barnolacesc/dockyard/commit/0cee87855169bc12369601d83d3097e39d04a7a3))
* **roadmap:** record CI approval blocker ([933e275](https://github.com/barnolacesc/dockyard/commit/933e2759d3f08fecc5feefb20a22861a74dc8939))
* **roadmap:** record Claude transcript CI ([ca2c86b](https://github.com/barnolacesc/dockyard/commit/ca2c86b9ae1b7a7c7643d3abf4586e2e23c1f16a))
* **roadmap:** record Claude usage probe CI ([50422e8](https://github.com/barnolacesc/dockyard/commit/50422e8ee90e5dc9d362aeb65228292b4d81091b))
* **roadmap:** record Codex probe CI ([cd98e15](https://github.com/barnolacesc/dockyard/commit/cd98e15b75f000e2e61c18bc3a19c2f3aaf8324e))
* **roadmap:** record description metadata CI ([fa722e2](https://github.com/barnolacesc/dockyard/commit/fa722e2112244eebbc97199bf4f52257e8b10182))
* **roadmap:** record editor containment evidence ([9a5f3b1](https://github.com/barnolacesc/dockyard/commit/9a5f3b10c5a6f6516774f26a8935dd5927e33b2e))
* **roadmap:** record editor containment PR ([76dee1f](https://github.com/barnolacesc/dockyard/commit/76dee1fa0859f7c203fad83be82887c109297a47))
* **roadmap:** record editor read CI ([63a531e](https://github.com/barnolacesc/dockyard/commit/63a531eaefee1ec41f7cf3732d47e1e2dd565195))
* **roadmap:** record editor save CI evidence ([8e214f1](https://github.com/barnolacesc/dockyard/commit/8e214f1eba4736ec9dc41c10445a6a0718728e5c))
* **roadmap:** record editor save pull request ([41e8f97](https://github.com/barnolacesc/dockyard/commit/41e8f979ba8bf48326515d473d016d532bf1e6ec))
* **roadmap:** record gitfile reader CI ([cd771d3](https://github.com/barnolacesc/dockyard/commit/cd771d38f335fadb06f5c7b75add00e3c2239801))
* **roadmap:** record helper verification CI ([5566692](https://github.com/barnolacesc/dockyard/commit/55666925e0ce2acf85f596ba1d281ae6c8c2e004))
* **roadmap:** record home path boundary PR ([2224027](https://github.com/barnolacesc/dockyard/commit/22240270bfb6ffbd443dc7188bdde02662f8ce26))
* **roadmap:** record issue preview CI ([d52722a](https://github.com/barnolacesc/dockyard/commit/d52722acad4c533fa9d9f8e2d4e28ed4b669a183))
* **roadmap:** record July 27 CI blocker ([5320ef8](https://github.com/barnolacesc/dockyard/commit/5320ef8ab1f82642526aa0f7532f221d9195b1e9))
* **roadmap:** record launch log retention CI ([02150b4](https://github.com/barnolacesc/dockyard/commit/02150b46f67b23bf06ddb51edd25d15a563e5591))
* **roadmap:** record launch-log CI evidence ([b7dae0c](https://github.com/barnolacesc/dockyard/commit/b7dae0c37bca4f85cd1042cac27af9f353ced9d4))
* **roadmap:** record launch-log privacy PR ([b7bfb29](https://github.com/barnolacesc/dockyard/commit/b7bfb293455381ca58563b507dd4803f8dcd78a4))
* **roadmap:** record localization drift PR ([7ef4fc7](https://github.com/barnolacesc/dockyard/commit/7ef4fc7498ad86a9d18feb771dc7051058ea53f0))
* **roadmap:** record login shell probe CI ([0e8726d](https://github.com/barnolacesc/dockyard/commit/0e8726ddb7eea1efcd5f51b02efe0cbb6ab0cef2))
* **roadmap:** record merged PR status CI ([cd15095](https://github.com/barnolacesc/dockyard/commit/cd1509530101c8bb2f0e2f8b31a23effadc096bb))
* **roadmap:** record Monaco containment PR ([532f37b](https://github.com/barnolacesc/dockyard/commit/532f37b5b79ecb0616b078949cf412e73e6a9683))
* **roadmap:** record Monaco resource CI ([693f48e](https://github.com/barnolacesc/dockyard/commit/693f48ec918e7828e507c306fb4c544d537909b2))
* **roadmap:** record native CI blocker ([4f1ce65](https://github.com/barnolacesc/dockyard/commit/4f1ce65c14c37b2c83009e903c0cfe891341b8d9))
* **roadmap:** record native validation ([a3a59b8](https://github.com/barnolacesc/dockyard/commit/a3a59b88c53f1be69741f0a96ca7163ec3b3b6e2))
* **roadmap:** record native watcher checks ([72d1d5e](https://github.com/barnolacesc/dockyard/commit/72d1d5e51cc25f0b734421c6cceeeacb819c05b8))
* **roadmap:** record OpenCode CI evidence ([95ea04e](https://github.com/barnolacesc/dockyard/commit/95ea04ecb8f8262d4f56e834e127782b44ec2448))
* **roadmap:** record OpenCode contract PR ([c04a5f3](https://github.com/barnolacesc/dockyard/commit/c04a5f307f7359a46cf9904681d0bc4d3fa48721))
* **roadmap:** record port watcher CI evidence ([2459a58](https://github.com/barnolacesc/dockyard/commit/2459a58aab55ceebdd214249ad96914f734b3a50))
* **roadmap:** record port watcher pull request ([ee64b35](https://github.com/barnolacesc/dockyard/commit/ee64b35d889609fa942a7747e9d2b0cbdefdfd97))
* **roadmap:** record power features CI evidence ([da3f68f](https://github.com/barnolacesc/dockyard/commit/da3f68f0fddaf355fd300cef39b956bb6c3687ee))
* **roadmap:** record push output CI ([652d9dd](https://github.com/barnolacesc/dockyard/commit/652d9dd91a9a9184594e95d672d61bbd0ee806a7))
* **roadmap:** record R20 native evidence ([f40847a](https://github.com/barnolacesc/dockyard/commit/f40847af4231adcb5c0caad7b26e2e13961306e4))
* **roadmap:** record R20 review state ([9718872](https://github.com/barnolacesc/dockyard/commit/9718872cb0fd9d3560c8378fa33c1b86405320f5))
* **roadmap:** record R47 native evidence ([71e19b3](https://github.com/barnolacesc/dockyard/commit/71e19b3e7f29f14d3d16f3e81ed57dd980431b60))
* **roadmap:** record R49 native evidence ([1694c3f](https://github.com/barnolacesc/dockyard/commit/1694c3f7a1fe40e8b152c1e0cca499e8351bec9e))
* **roadmap:** record R53 CI evidence ([60eba84](https://github.com/barnolacesc/dockyard/commit/60eba8402a11b0b5cb83d10008d1b10f792b3113))
* **roadmap:** record R53 review state ([58f3707](https://github.com/barnolacesc/dockyard/commit/58f37071e8ea1b21a5ad64ad0a6d4a16d1fcca2d))
* **roadmap:** record R56 CI evidence ([0f68022](https://github.com/barnolacesc/dockyard/commit/0f680221c29672115e33d013e9570aa86f83eaee))
* **roadmap:** record R57 CI evidence ([8b9dbfb](https://github.com/barnolacesc/dockyard/commit/8b9dbfb435f6df9d56d62c0518aef375e4f0fcae))
* **roadmap:** record R58 CI evidence ([253c6d4](https://github.com/barnolacesc/dockyard/commit/253c6d474cab601228780947bc88dfebfcb09ded))
* **roadmap:** record run-state CI evidence ([20ac7b5](https://github.com/barnolacesc/dockyard/commit/20ac7b59d28605df1a707c06f465599a9be00c55))
* **roadmap:** record script containment CI ([ce548f1](https://github.com/barnolacesc/dockyard/commit/ce548f14cb43e14f7c8114711788022409a3044e))
* **roadmap:** record script containment PR ([c28a246](https://github.com/barnolacesc/dockyard/commit/c28a246f7e6af7401d38e5442a84e32a8fa1a3d9))
* **roadmap:** record sidebar contrast PR ([8615b37](https://github.com/barnolacesc/dockyard/commit/8615b37d83036cfe5e884c5748e0abe5508850f4))
* **roadmap:** record stack detection CI ([4ea6fae](https://github.com/barnolacesc/dockyard/commit/4ea6faef7aff39935c04fbc42f26f99d7d32eb8e))
* **roadmap:** record stack metadata containment ([2b9f4f0](https://github.com/barnolacesc/dockyard/commit/2b9f4f0aaaade474f9c30a374392631c8fc6d480))
* **roadmap:** record state privacy pull request ([f522f3a](https://github.com/barnolacesc/dockyard/commit/f522f3a70f7776220047035b54b87656237fcfe9))
* **roadmap:** record subagent status CI ([cb978e2](https://github.com/barnolacesc/dockyard/commit/cb978e2dc69c468fcb2cefd7c092dd08c437afc2))
* **roadmap:** record tab snapshot recovery ([e74ca2d](https://github.com/barnolacesc/dockyard/commit/e74ca2ded3cf1d5112f300e1fee809c0f7193a65))
* **roadmap:** record tmux diagnostics CI evidence ([bc012bd](https://github.com/barnolacesc/dockyard/commit/bc012bdfe0414e74c36ce01b6ac05558c8ab19c2))
* **roadmap:** record tmux persistence PR ([900e40d](https://github.com/barnolacesc/dockyard/commit/900e40d7785001043f29508487b68bf4632b91b4))
* **roadmap:** record tool probe CI ([e18dd7e](https://github.com/barnolacesc/dockyard/commit/e18dd7ea873c3f6575d29cdce4b793c9d98c1e46))
* **roadmap:** record transient CI failure ([4428d3e](https://github.com/barnolacesc/dockyard/commit/4428d3e5305b60005d77160bf5f87a0e74afdd90))
* **roadmap:** record unified-log CI evidence ([622bb08](https://github.com/barnolacesc/dockyard/commit/622bb08266d5be794add57a99b3fa5ef745bdd32))
* **roadmap:** record unrelated CI flake ([1c65c55](https://github.com/barnolacesc/dockyard/commit/1c65c553adb76d733188fc5296cfa5eb952ba73f))
* **roadmap:** record unrelated native test flake ([7b711ed](https://github.com/barnolacesc/dockyard/commit/7b711ed125b67eaffbe0a46e3af261c1b3c1ff4d))
* **roadmap:** record workspace tour CI evidence ([4e97688](https://github.com/barnolacesc/dockyard/commit/4e97688834a0d10636bf0324fe737147a85717db))
* **roadmap:** record worktree purge CI ([1068139](https://github.com/barnolacesc/dockyard/commit/1068139905835475f3d783d3855eba0bc4f7e75a))
* **roadmap:** record worktree watcher PR ([2a3c88e](https://github.com/barnolacesc/dockyard/commit/2a3c88e667950f4ed0f73a4c1d9853a21f0cbe3c))
* **roadmap:** refresh pending PR evidence ([9d873bb](https://github.com/barnolacesc/dockyard/commit/9d873bba9ff8d8f79ad619ceff247eebd29225e2))
* **roadmap:** select private browser state ([2ddc4ec](https://github.com/barnolacesc/dockyard/commit/2ddc4ece5688d274373b2095cff266f2879cdb15))
* **roadmap:** specify quiet bottom statusline ([eaf0a9d](https://github.com/barnolacesc/dockyard/commit/eaf0a9daac62cb0a14bd43cdaca6943f40063b6c))


### CI/CD

* **localization:** validate bundle membership ([bbcba97](https://github.com/barnolacesc/dockyard/commit/bbcba970f5f7aa265ec32ef8bec3eb8534b6aaea))
* **localization:** validate bundle resource membership ([d782d72](https://github.com/barnolacesc/dockyard/commit/d782d728e47055e9ed262debf6c45711331fbf81))
* **localization:** validate privacy prompt parity ([d3068a8](https://github.com/barnolacesc/dockyard/commit/d3068a8edc417d6d6c0e7c8e0423fb9880ea489a))
* **localization:** validate privacy prompt parity ([08012ae](https://github.com/barnolacesc/dockyard/commit/08012ae9a6a1c50b41889af85bb7c6d3a2ddfb56))
* prevent new localization key drift ([d36ceaf](https://github.com/barnolacesc/dockyard/commit/d36ceafab1d3b9f381f5dac94b7673c68244b7f4))
* verify bundled helper integrity ([677b8ce](https://github.com/barnolacesc/dockyard/commit/677b8ce51e4855d9a9fbd7e22ec3be66d26f101d))
* verify bundled helper integrity ([cb332cd](https://github.com/barnolacesc/dockyard/commit/cb332cd7de2e313fa1517d5129a763de77afd6c6))

## [0.2.1](https://github.com/barnolacesc/dockyard/releases/tag/v0.2.1) (2026-07-11)


### Miscellaneous

* remove all sponsor links and pages ([1caa0e8](https://github.com/barnolacesc/dockyard/commit/1caa0e8f918b3f1e751f0a2c852db354e3d5f51f))
* remove all sponsor links and pages ([3e37f8c](https://github.com/barnolacesc/dockyard/commit/3e37f8c66b330250ee06c5b525f1031408bd63ff))


### Documentation

* check off homebrew tap in fork-separation TODO ([dbbc25a](https://github.com/barnolacesc/dockyard/commit/dbbc25a6839f7c3233908fb398d3164e420956d6))
* check off homebrew tap in fork-separation TODO ([917c2c4](https://github.com/barnolacesc/dockyard/commit/917c2c475048bb857cf4611077b6e117f3542f80))


### CI/CD

* add CodeQL, Dependabot, and SHA-pin remaining actions (VRA phase 3) ([508ae7a](https://github.com/barnolacesc/dockyard/commit/508ae7a37a37feff2984eb6f25a57a7bbf181e54))
* extend CodeQL to actions/javascript, tune Dependabot (issue [#48](https://github.com/barnolacesc/dockyard/issues/48) phase 3) ([a05abc6](https://github.com/barnolacesc/dockyard/commit/a05abc6cba4dd731b5b1a726014188430e472975))
