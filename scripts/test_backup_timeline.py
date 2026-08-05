from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
HEADER = (ROOT / "app" / "CCBGAppControllers.h").read_text(encoding="utf-8")
MAKEFILE = (ROOT / "app" / "Makefile").read_text(encoding="utf-8")
QUICK = (ROOT / "app" / "CCBGQuickConfigController.m").read_text(encoding="utf-8")
MORE = (ROOT / "app" / "CCBGMainTabBarController.m").read_text(encoding="utf-8")
TIMELINE = (ROOT / "app" / "CCBGBackupTimelineController.m").read_text(encoding="utf-8")


assert "CCBGBackupTimelineController" in HEADER
assert "CCBGBackupTimelineController.m" in MAKEFILE
assert '@"backupTimeline"' in QUICK
assert "CCBGBackupTimelineController new" in QUICK
assert "CCBGBackupTimelineController.class" in MORE

# Backups are data-validated, bounded in the UI, and never replace settings
# without first creating a recovery snapshot. Media files remain out of scope.
for token in (
    "CCBGBackupTimelineDirectory",
    "NSJSONSerialization",
    "NSPropertyListSerialization",
    "CCBGBackupTimelineLimit",
    "恢复前快照",
    "CCBGRestorePreferencesSnapshot",
    "dispatch_get_global_queue",
    "查看影响",
    "共享素材文件不会被删除或覆盖",
    "operationInFlight",
    "正在创建设置快照",
):
    assert token in TIMELINE, token

# Manual snapshots must use the utility work path and reject duplicate taps.
manual = TIMELINE.split("- (void)createManualSnapshot", 1)[1].split("- (void)restoreBackup", 1)[0]
assert "dispatch_async(dispatch_get_global_queue" in manual
assert "operationInFlight" in manual

restore = TIMELINE.split("- (void)restoreBackup:", 1)[1].split("- (void)tableView:", 1)[0]
assert restore.index("writeSnapshotWithReason") < restore.index("CCBGRestorePreferencesSnapshot")
assert "writeSnapshotWithReason" in TIMELINE

print("Backup timeline regression checks passed")
