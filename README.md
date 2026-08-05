# CleanCCBG2x2

## 2.3.0 配置与播放稳定性修复

- 基于正式 2.2.5 代码线，未引入后续版本的附加功能。
- 五模块占格修改后立即刷新，不再需要注销 SpringBoard。
- 配置模板、自动备份、备份时间机和设置导入统一使用原子恢复、写后校验与失败回滚。
- 设置备份改为后台序列化，修复导出时闪退和界面卡死。
- 损坏或连续无播放进度的视频会自动故障隔离，所有引用模块回退到健康素材。
- 清理失效的手动场景运行态，避免场景与普通自动化互相阻塞。
- 诊断与备份中新增“清除所有配置”，会保留素材文件。

## 2.2.5 素材库智能筛选

- 素材库搜索栏新增“最近”和“故障”筛选：最近按实际播放时间倒序显示，故障只显示已被运行时隔离的素材。
- 筛选仅使用已有的素材库元数据，不扫描文件、不重新解码视频，也不会向 SpringBoard 的控制中心展示路径增加工作。

## 2.2.4 备份时间机

- 新增“备份时间机”：直接查看自动与手动设置快照，显示创建时间、来源和设置项数量；恢复前会先自动写入“恢复前快照”。
- 每个快照可先查看与当前设置的影响项数量，再恢复或删除；整个流程只恢复偏好设置，不会删除或覆盖共享素材文件。
- “快捷 > 方案与恢复”与“更多 > 数据与方案”均可进入，方便在排查自动化或模块显示问题时快速回退。

## 2.2.3 回放、原生预览与全局控制

- 控制中心回放记录自动或手动命中的实际场景，并在恢复时固定该场景；新增结束回放，随时回到自动条件。
- 回放时间改用毫秒时间戳和本机时区格式显示，不再直接显示 UTC 风格的 `NSDate` 文本。
- “预览当前素材”的视频改用 iOS 原生播放器，提供系统播放控制与画中画路径；视频预览显示原始画面，控制中心内的模糊和变暗设置不受影响。
- 接力状态和测试改用 SpringBoard 已确认的运行上下文，避免 App 与控制中心环境不同导致误报未命中。
- 快捷页新增全局控制：暂停自动场景、记录当前状态、恢复最近状态和结束当前回放。

## 2.2.2 深色模式运行时识别修复

- 深色条件改为多来源判定：主线程优先读取系统屏幕与当前系统 trait，后台预热才回退到全局偏好、偏好文件和 SpringBoard 最近确认状态。
- 新增 UIKit 外观变化通知订阅，外观切换时立即失效场景缓存并重载五模块与系统/第三方覆盖层。
- 诊断报告新增 App 与 SpringBoard 两侧的外观候选值、最终采用来源和判定结果，避免再次只能根据现象猜测。
- 主线程已获得明确系统 trait 时跳过同步偏好与磁盘读取，不增加控制中心打开路径的 I/O。

## 2.2.1 场景条件与可用性修复

- 深色条件统一读取系统全局外观，不再被控制中心承载视图的固定浅色 trait 反向覆盖。
- 快捷页“预览当前素材”合并当前模块的有效画面配置，并为透明度、速率和循环补齐安全默认值，修复全黑预览。
- 跨模块接力新增实时状态、来源与目标说明及“立即测试接力”，明确仅在当前场景命中后双击来源五模块触发。
- 视觉策略新增实时状态说明，分别显示低电量封面、呼吸网格和感应式构图的开关、系统条件及等待原因。
- “当前命中”行不再在点按时清除手动场景，避免无提示改变场景启用方式。

## 2.2.0 快捷配置工作区

- 新增独立“快捷”Tab，集中提供五模块素材选择与预览、批量应用、模块设置复制，以及系统、第三方和更多工具入口。
- 新增最多 20 条的可撤销快捷修改历史；批量素材、完整复制、配置模板、性能档位、素材适配和冲突修复均采用一次写入、一次重载。
- 素材选择器新增“全部、收藏、最近”筛选，并保留搜索、缩略图和自动定位当前素材。
- 新增当前生效状态、自动化覆盖关系、未命中原因和可撤销的冲突处理；配置搜索可直接定位所有快捷功能。
- 新增流畅、均衡、画质三档性能策略，以及读取真实图片/视频尺寸的素材适配助手，可实时调整完整/填充和焦点后应用到当前模块。

## 2.1.9 场景开关行为修复

- 自动场景至少需要一个已启用条件；关闭唯一的专注条件后场景会立即退出，不再变成永久命中。
- 当前场景的接力开关成为唯一控制来源，双击来源模块接力成功后即使手势动作设为“无”也会给出触感反馈。
- 当前场景的低电量封面策略不再被已删除界面的旧全局值覆盖；设置页补充接力和三项视觉策略的生效条件。

## 2.1.8 场景导演精简与自动条件修复

- 删除场景自动条件中的时间段，删除分镜片段与情绪联动的设置、运行时和旧数据字段，减少播放器状态分支和高频信号回调。
- 专注模式改为独立开关；关闭后保留已选择的模式，重新开启无需再次选择。
- 修复锁屏、深浅色、充电和横竖屏条件的缓存失效与重载路径，系统/第三方模块也会在条件变化时重新解析场景素材。
- 方向变化增加布局稳定后的有界复查；同一素材不会因为环境通知重复重建播放器。
- 优先级用于解决多个自动场景同时命中的冲突：数值更高的场景先应用。
- 加固状态轨道和跨模块接力的旧备份数据校验，避免异常嵌套值导致 SpringBoard 崩溃。

## 2.1.7 场景状态恢复与控制中心性能修复

- 专注模式变化后按 0.08、0.35、0.90 秒进行有界重新采样，等待系统活动状态稳定；仅在专注签名真正变化时重载模块。
- 深色/浅色外观变化会先失效场景运行时缓存，场景导演、组合规则和五模块基础外观自动化统一使用已挂载控制中心的外观上下文。
- 系统与第三方模块的一次完整更新只读取一次偏好快照，并复用已经解析的素材，减少打开控制中心时的主线程同步工作。
- 诊断报告新增场景运行时上下文、解析场景、手动场景和条件摘要，便于直接定位设备上的自动化命中问题。

## 2.1.6 专注场景退出、切换与即时恢复

- 系统明确报告当前没有专注模式时，立即清除上一次保存的活动别名，不再把“工作”等旧状态当作仍然开启。
- 订阅 `FCActivityManager` 的进入、退出、切换和可用模式变化，连续回调合并为一次全局素材重载；切换到其他专注模式也走同一状态机。
- 模式列表发现和当前活动状态使用独立缓存；Focus 变化时同步失效当前别名、场景上下文和场景命中三层缓存，五模块及系统/第三方模块恢复各自原素材。
- 观察器注册沿用 0、0.8、2.0 秒有界重试，成功后停止，不增加常驻轮询或控制中心布局工作。

## 2.1.3 专注模式、CCSwitch、回放与控制中心性能修复

- 专注模式改为枚举 DND/Focus 服务的只读运行时接口，并补充系统偏好域读取；诊断报告会记录尝试过的 selector、返回类型和命中数量。
- 为 `netskao.ccswitchdatamodule` 记录原生展开/收起回调状态，紧凑与展开分别绑定各自素材，同时兼容单击和长按展开路径。
- 合并五模块重复的延迟收敛任务、层级诊断和首帧回放快照，缓存同一轮场景上下文，降低首次打开控制中心时的主线程与偏好写入压力。
- 控制中心回放增加“记录当前视觉状态”、空状态说明和恢复成功提示；恢复后主动触发已挂载模块的呈现修复，诊断导出附带回放数量与最近记录。

## 2.1.2 专注模式发现与 App 安全性能修复

- 显式加载系统专注模式私有框架，并由 App 通过 Darwin 通知请求 SpringBoard 刷新；选择页延迟重读共享缓存，诊断报告记录框架、服务和配置文件解析状态。
- 模块状态、诊断页和场景回放改为页面级素材快照，避免每个 cell 重复扫描素材目录和偏好数据。
- 完整备份导出/恢复移到后台，导出采用流式 JSON；过滤异常历史、方案、规则和备份媒体路径，降低卡顿与崩溃风险。
- 配置方案不再递归包含方案列表，应用旧方案时也不会删除后来创建的其他方案。

## 2.1.1 专注模式、诊断页与场景入口修复

- 补充现代 iOS DND 状态与配置服务读取，合并当前专注模式和历史缓存，让场景导演可以列出控制中心识别到的专注模式。
- 诊断与备份页面统一使用安全数据源，兼容旧版本遗留的异常偏好值，避免进入页面时闪退。
- 删除会静默编辑错误场景的五个全局“视觉演出”入口；分镜、情绪联动、状态轨道、接力和视觉策略统一从具体场景详情进入。

## 2.1.0 稳定性审计与场景导演完整运行链路

- 将控制中心宿主布局改为轻量几何更新，仅在紧凑/展开状态或模块类型真正变化时重载素材，并持续修正视频层级和第三方展开尺寸。
- 将播放健康度、时间线和诊断写入移出控制中心主线程，合并第三方运行状态提交，降低首次打开、展开和收起时的卡顿风险。
- 滑块拖动期间只更新数值显示，松手后保存一次，同时兼容 VoiceOver 和键盘等非触摸调整。
- 完整保留场景导演、状态轨道、分镜、情绪联动、低功耗封面、回放时间线和素材健康度功能。

- 场景导演移到独立底部 Tab，自动场景使用挂载界面的深浅色、可选择的专注模式以及真实锁屏、充电和方向状态。
- 情绪联动实时跟随音量、亮度、网络和音乐播放，只更新显示参数，不重建系统或第三方模块播放器。
- 低电量策略暂停当前视频并显示当前位置封面，退出低电量后从原位置继续；分镜结束后恢复模块原素材。
- 素材健康度统计首帧延迟、平均播放时长、失败和内存压力；回放时间线包含五模块、系统模块和第三方模块视觉状态。

## 2.0.102 CCSwitch transition stability

- Ensures a third-party module with a direct content controller is owned by that controller alone; the generic container is now fallback-only.
- Removes duplicate third-party disappearance, suppression, and delayed-restore callbacks that could stall Control Center during the first CCSwitch expansion and again while collapsing it.

## 2.0.101 Automation visibility and generic conflict repair

- Keeps automatic-dimension rows visible so the five-module appearance, sizing, privacy, and orientation settings render again.
- Forces full ancestor hierarchy recovery after preference and environment media changes, preventing appearance automation from leaving modules occluded until wake.
- Bounds third-party module identity discovery and removes recursive discovery from repeated layout passes to avoid incompatible modules stalling Control Center.
- Retries the configured compact/generic video after transient playback failures without advancing or persisting the first library video.

## 2.0.100 Five-module behavior and generic presentation repair

- Separates expandable third-party modules into compact/expanded media and leaves native tap/long-press handling untouched; non-expandable modules retain click-to-toggle off/on media.
- Adds explicit adaptive/manual expanded sizing for the five modules and makes manual width/height effective only in manual mode.
- Repairs privacy media loading, scene-based orientation media, reusable gesture haptics, and native expanded-player touch handling.
- Keeps automation media temporary in fixed, sequential, and random modes so disabling appearance or other automation restores the pre-automation media without unmounting the module.

## 2.0.99 Collapse recovery and neutral gesture switching

- Posts a dedicated presentation-recovery notification when the in-Control-Center default/restore module finishes collapsing, so five-module host ordering is repaired after the expanded container is gone without reloading media again.
- Keeps third-party overlay playback running through the native 0.42-second dismissal animation, avoiding an `AVPlayerLayer` fallback to the video's first frame before removal.
- Switches double-tap previous/next media without applying the configured MoveIn/Push transition, preventing videos from flying in from the screen edge.

## 2.0.93 Generic transition fade-out

- Clears generic overlay visual layers before immediate detach to avoid black-frame collapse artifacts.
- Restores overlay visual layers on the next compact/expanded playback show path.

## 2.0.90 Generic module tap state and lifecycle

- Adds independent off/on-state media for generic Control Center modules, selected from the module's runtime `active` / `selected` / `on` / `state` values.
- Preserves native Control Center expansion behavior; generic media overlays no longer install or replace third-party expansion methods.
- Simplifies the generic module settings page to state media only; non-expandable modules no longer show misleading compact/expanded media, playlist, or playback rows.
- Long-press selection in Control Center now writes the current on/off state media for generic modules instead of hidden compact/expanded media keys.
- Starts system and generic overlay videos with `playImmediatelyAtRate:` on load, visibility restore, and loop restart to reduce expanded-video startup delay.
- Generic modules no longer infer third-party internal state; every tap toggles the plugin-managed off/on media state.
- Delays generic overlay hide/reconcile during native expand-collapse transitions and restores compact overlays after expanded controllers disappear.

## 2.0.76 Universal Control Center modules and mounted recovery

- Adds an "Other Control Center Modules" menu that discovers system and third-party modules, then gives every selected module its own compact/expanded media, playlist, playback, gesture, and visual settings.
- Re-converges each custom module's host ordering after every reload and performs a bounded full host-hierarchy repair on first mount and after Apply Default/Restore, with delayed passes for the post-respring render transition.

## 2.0.75 AVPlayerLayer first-frame blank guard

- Keeps the retained thumbnail/cover visible until `AVPlayerLayer.readyForDisplay` is true, avoiding blank Control Center tiles after respring or media switching when the player clock advances before the render surface is ready.
- Rebuilds the player layer surface when a mounted module stays not-ready, and logs `playerLayerReady`, player status, and player time in mounted presentation traces.

## 2.0.74 Control Center mounted visibility convergence

- Re-converges the module view, player layer, layout, and playback after Control Center window attach, view appearance, reload notifications, and in-Control-Center media selection.
- Adds lifecycle traces for mounted presentation convergence to diagnose any remaining post-respring or post-reload blank module state.

## 2.0.73 Default/restore visual convergence

- Forces the next mounted reload after Apply Default or Restore to honor the freshly written per-slot preference media, so sequence/random modules do not keep displaying the temporary default video.
- Extends lifecycle traces with the selected media name and the persisted current media used during reload.

## 2.0.72 Default/restore write reliability

- Executes the Apply Default and Restore state writes synchronously from the expanded buttons, so Control Center cannot discard the operation when the expanded controller changes state.
- Adds lifecycle trace entries that record default snapshot creation and restoration completion.

## 2.0.71 Default/restore long-press interaction

- Restores the expanded default/restore action interface on a long press while retaining the iOS 16 expanded-content size selectors required to avoid the crash.

## 2.0.70 Default/restore synchronization repair

- Defers the five-module default/restore write until the Control Center action alert has dismissed, then sends one bounded follow-up reload so all mounted modules converge without lock/wake or respring.

## 2.0.69 Default/restore iOS 16 long-press crash repair

- Restores `preferredExpandedContentWidth` and `preferredExpandedContentHeight` on the default/restore content controller because iOS 16 queries them during the long-press transition even when the module rejects functional expansion.

## 2.0.68 Default/restore long-press safety

- Explicitly refuses the Control Center expanded-module transition for the 1x1 default/restore utility, so a long press cannot dispatch to a missing private-protocol handler.
- Presents the default/restore alert only through the attached utility controller and ignores duplicate or dismissing presentation requests.

## 2.0.67 Default/restore Control Center stability

- The 1x1 default/restore module now presents its actions without expanding inside Control Center, preserving the current custom-module grid position.
- Applying or restoring the five default media selections no longer repositions the Control Center content area.

## 2.0.63 Module lifecycle diagnostics

- Exports bounded lifecycle traces for the five custom Control Center modules to diagnose startup mounting failures.

## 2.0.62 Video mount stability

- Does not reload a custom module while its selected video player is still preparing.
- Keeps initial module mounting and per-module media switching on the same player lifecycle.

## 2.0.61 Control Center startup layout stability

- Stops background-overlay startup work from repeatedly forcing CCSupport to recompute the five persistent module sizes.
- Keeps custom module dimensions available through the explicit size controls only.

## 2.0.60 CCSupport runtime size compatibility

- Uses CCSupport's `0=portrait, 1=landscape` size callback convention.
- Reads configured grid dimensions from the named user-defaults domain without synchronous preference I/O during Control Center layout.

## 2.0.59 startup Control Center size reload

- Restores each module's configured runtime grid size.
- Requests five bounded CCSupport size recalculations during SpringBoard startup so the first Control Center layout includes every module without a lock/wake cycle.

## 2.0.58 static Control Center module registration

- Registers each media module with its fixed plist grid size instead of the unreliable runtime size query during the first Control Center layout after a SpringBoard restart.
- Preserves the five intended sizes: 2x2, 1x2, 2x3, 3x2, and 3x3.

## 2.0.57 SpringBoard video recovery

- Allows modules to play readable media after a SpringBoard restart even when UIKit still reports protected data as unavailable; privacy mode remains protected.
- Retries the mounted module reload without waiting for a protected-data notification, so changing media no longer requires a lock/wake cycle.

## 2.0.56 media-directory reload recovery

- Distinguishes an unreadable media directory from a successfully enumerated empty directory, so temporary SpringBoard access failures cannot clear any of the five module states.
- Keeps the displayed item during an incomplete reload and retries when a reload notification arrives, so selecting media does not make the affected Control Center module disappear.

## 2.0.55 protected-media mount recovery

- Keeps persisted media catalog entries available while SpringBoard protected data is temporarily unavailable, preventing all five modules from being cleared after a respring.
- Uses a stable placeholder and defers file access, video decoding, and playback statistics until protected data becomes readable; media changes use the same retained-state path.
- Extends the bounded first-mount recovery window so modules recover without requiring a lock/wake cycle.

## 2.0.54 Control Center master switch

- Adds a standalone 1x1 Control Center switch with ON and OFF states.
- OFF stops and hides all five custom modules and system overlays while preserving every saved media choice and playback state; ON restores them through the normal reload path.

## 2.0.53 retained video cover repair

- Retains the prior frame or a stable placeholder while replacement videos initialize, so Control Center modules never present an empty rendering surface during a media change or first mount.
- Keeps expanded native video output behind the cover until a decoded frame is ready, matching compact and expanded first-frame behavior without unsafe AVPlayer preroll.

## 2.0.52 startup playback and Volume host repair

- Keeps first-mounted custom-module videos in a bounded Ready-state wait for about ten seconds, rather than abandoning startup after 0.9 seconds under five-way decoding load.
- Refreshes Brightness and Volume overlay media at 0.75, 2, 4, and 7 seconds after SpringBoard starts, removing the dependency on an App tab refresh before video playback begins.
- Reads positive expanded state from the nearest Volume host controllers before compact fallback, keeping compact and expanded selections separate on controller variants without an explicit expanded class.

## 2.0.51 Control Center mount and Volume presentation repair

- Retries missing custom-module media from the actual Control Center window-attachment event, covering delayed SpringBoard data availability after a restart.
- Reduces mounted video readiness polling overhead without restoring unsafe AVPlayer preroll.
- Classifies Volume expanded presentation from positive runtime state and panel geometry before treating a slider's negative state as compact, so compact and expanded media remain independent.

## 2.0.50 SpringBoard safe-mode repair

- Removes explicit AVPlayer preroll calls that could throw before the player reached `AVPlayerStatusReadyToPlay` and send SpringBoard into a safe-mode loop.
- Keeps the 2.0.49 first-Control-Center mount recovery, immediate playback, and first-frame cover handling without the unsafe preroll request.

## 2.0.49 first-mount and playback latency repair

- Recovers all five custom modules on the first Control Center presentation after a SpringBoard restart, without waiting for a lock/wake cycle.
- Treats a selected video without an attached player item as an incomplete mount and retries the mounted reload with a strict bound.
- Prerolls paused videos, resumes with immediate playback, and removes the cover as soon as the first video frame is ready.

## 2.0.48 stop compact slider failure advancement

- Stops Brightness and Volume compact startup playback failures from advancing to the next video or changing current media.
- Retries the same compact slider video twice and keeps its configured cover/current selection if playback is still unavailable.
- Repairs current compact sequential/random state from the configured compact media and clears failure counts left by 2.0.46/2.0.47.

## 2.0.47 deterministic compact slider media fallback

- Eliminates the arbitrary first-video fallback for compact Brightness and Volume overlays when compact media is configured.
- Uses the configured compact media if a dynamic compact current item is unavailable after SpringBoard startup.
- Stops parent-controller expansion state from overriding the actual slider/current-controller state during compact initialization.

## 2.0.46 Brightness/Volume compact media persistence

- Prevents compact Brightness and Volume videos from resetting to the first library item after SpringBoard restarts.
- Prioritizes the actual slider's expansion state during startup before falling back to controller state and size heuristics.
- Persists runtime current-video changes in the explicit current-user/any-host preference scope while preserving independent fixed, sequential, and random state.

## 2.0.45 independent Music compact/expanded videos

- Restores separate Music compact and expanded video selections, playback modes, playlists, and remembered current items.
- Uses the Music controller's runtime expansion state before class and size fallbacks, so expanded hosts no longer read compact media keys.
- Corrects the mistakenly released 2.0.44 shared-state behavior while retaining the 2.0.43 slider background fixes.

## 2.0.43 capsule-clipped brightness and volume backgrounds

- Routes module gestures through the module-owned Control Center host and allows simultaneous host recognition.
- Accepts touches wrapped by Control Center controls so configured tap/long-press and expanded swipe/pan actions fire.
- Uses the Control Center module tap callback for reliable configurable single/double/triple actions and a real animator-driven blur intensity.
- Adds bounded, delayed Brightness/Volume controller discovery with safe runtime superclass checks.
- Includes the complete 2.0.37 module isolation and 2.0.36 repair set.

## 2.0.38 gesture host and slider-overlay discovery repair

- Routes module gestures through the module-owned Control Center host.
- Adds bounded Brightness/Volume controller discovery with safe superclass checks.

## 2.0.37 cross-module reload isolation repair

- Prevents a global settings notification from rebuilding unchanged module players.
- Coalesces repeated reload notifications per module and avoids unnecessary first-mount reloads.
- Includes the complete 2.0.36 gesture, slider, initialization, and five-module performance repair set.

## 2.0.36 stable-base gesture and slider repair

- Returns the runtime to the stable 2.0.32 baseline and removes player skinning, broad class scans, eager loading, and repeated mount retries.
- Keeps configurable compact/expanded single, double, triple, and long-press actions with haptics.
- Keeps independent per-module opacity and blur gestures: left-side vertical adjustment controls blur, right-side controls opacity.
- Repairs Brightness/Volume attachment with explicit Audio-module support and narrowly scoped shared-slider host detection.

## 2.0.32 application information architecture redesign

- Rebuilds the settings App around Overview, Modules, Media, System, and More tabs.
- Makes module scope explicit and keeps five-slot configuration, defaults, and copy operations isolated.
- Shows one system-overlay editor at a time and requires all five defaults before applying a reversible transaction.

## 2.0.31 utility module and expanded-state correction

- Adds a standalone 1x1 Control Center module whose expanded view applies or restores five independently configured defaults.
- Corrects Music and Connectivity expanded-state detection after the 2.0.30 device regression.
- Removes the incorrectly embedded default/restore button from the five media modules.

## 2.0.30 playback state, Control Center, and settings redesign

- Separates fixed, sequential, and random state for compact and expanded system-module backgrounds.
- Adds brightness and volume module backgrounds plus a reversible five-module default action.
- Makes the Control Center media picker dismissible by swiping down and prevents expansion from opening it.
- Reorganizes the settings App and shows all five labeled module previews.

## 2.0.29 device UI and overlay state repair

- Playback settings, independent playlists, and media detail rows no longer hide every automatic-height cell.
- Media thumbnails use QuickLook first, persist successful previews, and fall back to bounded AVFoundation generation.
- Connectivity/Music compact and expanded selections keep fixed and current state aligned, with deterministic row mapping and clearer start-background labels.

## 2.0.28 fixed/current isolation and mutually exclusive settings

- Fixed/constant mode now rejects left-right switching across all five custom sizes and the Connectivity/Music overlays.
- Custom modules reload on every remount, recover when protected data becomes available, and preserve existing state during transient locked catalog reads.
- Video thumbnail workers have bounded timeouts, image previews fall back when QuickLook stalls, and failed jobs always release their shared worker slot.

## 2.0.26 conflict-safe system-overlay state

- Manual selection, automatic playlist advance, and failure recovery now use separate transition paths with explicit priority.
- Failed videos are quarantined from automatic playback, recovery is capped at three consecutive skips, and manual selection retries a quarantined item.
- Expanded aspect adaptation resizes only the media container while the overlay remains aligned with the native Control Center host.
- System-overlay settings send one reload per change, and effect sliders commit only when dragging finishes.

## 2.0.25 system-overlay playlists and adaptive video frames

- Connectivity and Music have independent compact and expanded video playlists with fixed, sequential, and random playback.
- The long-press picker includes playlist, favorites, and recent scopes; favorites can be changed with a trailing swipe action.
- Swipe, long-press, haptics, automatic failure skipping, and expanded aspect-adaptive frames are configurable per system overlay.

## 2.0.24 automatic readiness and system-overlay controls

- Custom modules refresh once after their first real Control Center mount, removing the manual first refresh.
- Music and Connectivity overlays reload automatically when selected video assets become playable.
- Swipe left or right on non-control areas to switch the current compact, expanded, or network-state video.
- Long-press a blank overlay area to open a searchable video picker without intercepting native buttons and sliders.

## 2.0.23 first-open and Music playback repair

- Selecting compact or expanded system-module media now atomically enables the overlay and video gate.
- Existing Music MP4 selections migrate out of the disabled 2.0.22 state without merging compact and expanded choices.
- Compact custom modules resume their persistent player after the view actually enters a Control Center window.
- Music overlays queue playback whenever their real compact or expanded host becomes visible.

## 2.0.22 reusable compact video playback

- Compact custom modules render video through a persistent `AVPlayerLayer`; expanded presentation alone uses native AVKit controls.
- Rapid completed swipes replace the current player item immediately without rebuilding the player graph.
- Video-library thumbnails use bounded asynchronous frame generation, and system Music/Connectivity overlays reuse their player layers.
- Repeated SpringBoard restarts remain diagnostic-only and no longer silently disable all system overlays.

## 2.0.21 stable Music host and responsive switching

- 系统音乐覆盖层每次刷新直接读取当前媒体目录，不再被异步旧快照永久卡在静态素材。
- 配置签名加入素材解析状态，素材由未解析变为可用时强制重建播放器。
- 常显模式在 `selectedMedia` 缺失时使用有效的 `currentMedia` 并自动修复引用。
- 音乐诊断会明确报告素材缺失、视频开关关闭或正在使用系统封面。

## 2.0.17 diagnostics export repair

- 修复设置应用导出诊断报告时闪退的问题，改用系统文件导出选择器。
- 导出前验证 JSON 数据并显示可读错误，不再静默失败。
- “音乐播放状态”支持点击查看完整内容并一键复制。

## 2.0.16 compact lifecycle and music diagnostics

- 自定义模块在 `viewDidLoad` 即进入可播放状态，紧凑态不再依赖 Control Center 不保证调用的 `viewWillAppear:`。
- 紧凑模块挂载时直接启动当前视频，保留原生紧凑视频表面与展开控制条。
- 诊断页新增音乐播放状态，显示资源状态、时间控制状态、速率、播放时间和原生播放器可见性。

## 2.0.15 native compact video surfaces

- 五个自定义模块的紧凑视频改用无控制条的原生 `AVPlayerViewController`，不再依赖控制中心紧凑宿主中的直接 `AVPlayerLayer`。
- 长按展开时复用同一原生播放器并显示系统控制条，收起后自动关闭控制条并恢复紧凑视频表面。
- 音乐系统模块改用无交互的原生播放器子控制器；连接模块继续使用原有稳定渲染路径。

## 2.0.14 compact selection and music frame reveal

- 修复控制中心素材列表设为常显后，紧凑模块消失、只有长按展开才出现的问题。
- 选择结束后按实际窗口状态恢复紧凑播放器，并强制退出残留的展开播放器呈现。
- 音乐模块在播放时间实际前进后撤掉静态首帧，不再只依赖系统宿主的图层就绪标记。

## 2.0.13 SpringBoard startup-safe overlay cache

- 修复后台首帧预热过早创建 `UIImage`、导致 `UIScreen.mainScreen` 为空并触发无限安全模式的问题。
- 后台视频首帧缓存改用 ImageIO 和 JPEG 数据，只有控制中心视图出现后才在主线程创建图片。
- 保留无 KVO 播放就绪检查、控制中心提前挂载和素材目录缓存。
- 新增系统覆盖层崩溃循环保护，连续异常启动时自动跳过高风险覆盖层。

## 2.0.12 SpringBoard safety rollback

- 移除系统音乐与连接覆盖层上的全部 AVFoundation KVO，修复 2.0.11 无限安全模式回归。
- 改用有次数上限且带播放器代次校验的异步就绪检查，旧播放器销毁后任务自动失效。
- 保留控制中心出现前挂载、素材快照缓存和视频首帧磁盘缓存。

## 2.0.11 system overlay playback readiness

- 音乐模块在视频资源就绪后主动恢复播放，不再停在静态首帧。
- 视频画面真正可显示后才移除封面帧，避免黑屏或闪烁。
- 音乐与连接覆盖层提前到控制中心出现动画前挂载。
- 后台缓存素材目录与视频首帧，移除控制中心主线程的全库扫描。

## 2.0.10 safe native playback and overlay preloading

- 修复 `AVPlayer` 未就绪时预缓冲导致 SpringBoard 无限安全模式的问题。
- 原生视频控制器只在展开视频后懒加载，保留播放、时间进度与拖动控制。
- 展开窗口在后台读取素材比例并自适应，不阻塞控制中心主线程。
- 音乐与连接模块预热视频资源和首帧，减少首次打开控制中心的空白等待。
- 媒体库优先使用系统 Quick Look 生成真实视频缩略图。

## 2.0.9 preview and native playback repair

- Settings previews now follow the active module's current item, constant selection, and independent playlist.
- Media-library thumbnails use consistent cache identities and bounded concurrent generation so one video cannot block the full list.
- Expanded custom modules use native AVKit playback controls with time progress and media-aspect-aware window sizing.
- Current videos prepare before Control Center appears and reuse cached first frames to remove the blank opening delay.
- Music overlays arbitrate compact/expanded ownership, suppress conflicting system artwork/shadows, and recover stalled playback.

## 2.0.8 system overlay playback update

- Keep compact and expanded Connectivity/Music selections independent, including controllers that expand in place.
- Refresh the selected Connectivity background immediately when the presentation or network state changes.
- Prevent explicit Music videos from being repeatedly rebuilt by live artwork updates.
- Improve video start/loop behavior, aspect-fill defaults, rounded clipping, overlay ordering, and fade transitions.

## 2.0.7 media list performance update

- 素材选择列表、设置页媒体库、分组素材列表统一改为先显示轻量占位图，再在后台生成图片/视频缩略图，避免滑动时同步抽视频帧。
- 缩略图请求会合并：同一个素材正在生成预览时，后续 cell 只挂回调，不重复排队解码同一个视频。
- App 与控制中心素材选择器共用 `/var/mobile/Library/CleanCCBG2x2/Thumbnails` 磁盘缩略图缓存，视频封面会优先复用已生成结果。
- 控制中心选择素材弹窗支持中文搜索与中文筛选项，诊断与维护页面的剩余英文说明已改为中文。
- 系统连接/音乐模块背景继续收紧只由根控制器持有，降低紧凑/展开状态串图和音乐展开中央黑影的风险。

## 2.0.6 media-state hotfix

- 修复顺序/随机模式下展开模块拖动透明度后回到固定旧素材的问题；运行中重载会优先保留当前播放项。
- 修复常显模式从媒体库切换素材后仍显示旧素材的问题；手动选择会同步当前素材并立即刷新。
- 展开模块播放视频时显示进度滑杆，可拖动调整播放位置。
- 媒体库顶部增加封面预览，左上角眼睛快捷按钮已移除。
- 所有通用滑杆支持连续调整，双击数值可手动输入精确值。
- 模块切换动画加入更柔和的 timing，外观与隐私设置修改后会立即通知控制中心刷新。
- 音乐模块和连接模块支持紧凑/展开两套背景素材，默认以完整适配显示，减少过度拉伸。
- 自动备份列表支持左滑删除单个备份文件。

## 2.0.3 live runtime grid sizing

- 修改模块整数格数后会立即通知 CCSupport 刷新布局缓存，不再需要注销 SpringBoard。

- 五个模块均启用 CCSupport 运行时尺寸回调，可为当前模块独立选择 1–4 格宽度和 1–4 格高度。
- 竖屏使用所选宽高，横屏自动交换宽高；非法或缺失设置回退到该 bundle 原始注册尺寸。
- App 的“模块”页面显示当前整数占格并提供应用提示。关闭并重新打开控制中心即可刷新，CCSupport 缓存未更新时注销一次。
- 控制中心占格与点开后的展开宽高互相独立；视频继续按实际模块边界自适应。

## 2.0.1 performance and interaction update

- 素材洞察改为后台一次性读取文件元数据并缓存排序，避免主线程重复磁盘 I/O。
- 文件哈希按大小与修改时间复用缓存，主色提取使用低内存 ImageIO 缩略图，长任务支持取消和进度显示。
- 设置滑杆拖动时只更新显示，松手后一次写入，减少偏好同步和控制中心重载。
- 每个模块可独立调整展开宽度与高度；图片和视频会在模块尺寸变化后重新适配边界和焦点。
- 点按控制中心模块可弹出素材列表并手动切换，紧凑内容视图仍不挂载触摸手势。

## 2.0.0 complete expansion

- 素材分组、标签、收藏分组与记忆式展开/收缩；支持批量编辑、SHA256 重复检测、引用迁移合并和存储清理建议。
- 五个模块拥有独立播放列表、拖动排序、随机防重复、图片独立停留时间、视频播放次数策略、GIF/Live Photo/短视频和下一项预加载。
- 新增素材有效期、组合自动化、定时分组、规则冲突说明、隐私模式、横竖屏独立素材/裁剪、模块外观预设和自动取色。
- 新增播放统计、实时进度、下一项、历史与跳过操作、故障隔离、五尺寸预览、主屏幕快捷操作、完整配置方案、自动快照和一键回滚。

## 1.4.0 update

- 连接模块可按 Wi-Fi、蜂窝网络和离线状态自动选择不同背景素材。
- 播放器模块可使用实时专辑封面，封面不可用时自动回退到共享素材库中的指定背景。
- 连接模块和播放器模块分别支持填充方式、透明度、模糊、压暗以及视频回退设置。
- 系统模块增强层只绘制背景，不接管或修改 Apple 原有按钮、手势与播放控制。

## 1.3.2 update

- 媒体库支持展开和收缩，并记住上次状态；搜索、筛选或导入时会自动展开。
- 顺序/随机轮播中的图片按设定间隔切换，视频会等到完整播放结束或到达裁剪终点后再切换。
- 修复系统深浅色自动化不能实时跟随、素材工具按钮闪退和紧凑模块显示文件名的问题。
- 新增界面主题色与浅色/深色风格，模块使用连续圆角，展开后可持续上下拖动调整透明度。

面向 iOS 16 的 clean-room 2x2 控制中心媒体背景模块。项目不包含也不修改任何第三方插件的验证逻辑或二进制代码。

## 1.3.2 功能

- 五个尺寸模块共享同一套素材库；每个模块的常显素材、轮播、显示性能与自动化配置均独立保存
- 新增模块配置中心，可快速切换正在配置的尺寸，并显式复制或单独重置某个模块配置
- 素材库支持搜索、图片/视频/收藏筛选、长按快捷操作，并修复筛选状态下操作错位
- 自动化规则可按模块分别设置，升级时会保留并迁移 1.3.0 的现有规则
- 同一素材在不同尺寸模块中可分别设置裁剪焦点、效果、透明度、随机权重与视频播放参数
- 素材选择器支持搜索；选择停用素材时会自动启用，系统模块背景仅使用可用素材
- 设置备份采用完整替换与兼容迁移，索引重建会清理缺失文件留下的模块引用

- 1x2、2x2、2x3、3x2、3x3 五个独立控制中心模块
- 长按进入系统展开预览，展开后左右滑动切换素材、上下滑动调整透明度
- App 内选择当前配置模块，各尺寸独立保存常显素材和播放设置
- 独立主屏幕设置 App，不依赖 PreferenceLoader 才能配置
- 图片和视频批量导入，缩略图媒体库、排序、重命名、启用、停用和删除
- 支持从系统相册或文件 App 多选导入
- 支持在 Filza 中定位单个素材或整个素材目录
- 素材收藏、仅播放收藏、随机权重、文件信息和单项参数重置
- 常显单个素材、顺序轮播和随机轮播；常显模式可以手动指定任意视频
- 每个模块可为同一视频独立设置静音、循环、速度、开始时间和结束时间
- 每个模块可为同一素材独立设置完整/填充、模糊、压暗、饱和度、对比度、透明度和焦点
- App 内图片/视频预览
- 昼夜时段、浅色/深色模式、工作日/周末、低电量和充电状态自动切换
- 低电量时禁止视频、仅充电播放视频、记住上次素材和展开时随机
- 媒体数量与存储诊断、模块立即刷新、索引重建、缓存清理和诊断报告导出
- JSON 设置备份和恢复
- 可选为 Apple 连接模块和音乐模块的展开界面添加图片/静音视频背景
- 设置和素材变更通过 Darwin 通知实时刷新，不需要注销 SpringBoard
- RootHide 路径、pkgmirror、3 个 AutoPatch 和无 PAX 的 GNU tar 打包

## 安装和使用

1. 通过 Sileo 或 Zebra 安装 `com.zjc.cleanccbg2x2_2.3.0_roothide_iphoneos-arm64e.deb`。
2. 仅首次安装或升级控制中心 bundle 后，重新加载 SpringBoard 一次，让系统发现模块。
3. 从主屏幕打开 `2x2 Background`，点右上角加号导入图片或视频。
4. 在媒体库点一下素材即可把它设为常显；点右侧详情按钮可设置该素材的全部参数。
5. 打开控制中心编辑页面，添加 `Clean 2x2 Background`。

模块被系统发现后，App 内后续设置、素材选择、轮播和自动化修改都会立即发送 `com.zjc.cleanccbg2x2/reload`，无需再次注销。紧凑模块不接收手势；只有系统长按展开后才启用左右滑动，收起时立即关闭交互。

## Windows 构建

本项目依赖 Theos、Xcode iPhoneOS SDK 和 macOS 代码签名工具，因此 Windows 本机不能直接编译 arm64/arm64e Mach-O。仓库内的 GitHub Actions 工作流负责：

1. 验证源码、plist 和 RootHide 转换器。
2. 在 macOS 上使用 Theos 编译 rootless 包。
3. 转换为 RootHide 布局并检查 pkgmirror、AutoPatch、GNU tar 和模块尺寸。
4. 发布 `CleanCCBG2x2-RootHide` artifact，并把结果同步到 `build-artifacts` 分支。

推送 `main` 即可触发构建。成功产物名为：

```text
com.zjc.cleanccbg2x2_2.3.0_roothide_iphoneos-arm64e.deb
```

## 本地静态验证

```powershell
python scripts/validate_source.py
python scripts/test_repack_roothide.py
```

这些检查验证源码、plist 和包结构，设备上的 SpringBoard 运行情况仍需在真机测试。若模块导致安全模式，需要提供最新的 `SpringBoard-*.ips` 崩溃日志才能定位具体调用栈。
