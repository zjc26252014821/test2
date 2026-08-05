from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCE = (ROOT / "shared" / "CCBGMediaCatalog.m").read_text(encoding="utf-8")


def body(start: str, end: str) -> str:
    return SOURCE.split(start, 1)[1].split(end, 1)[0]


def test_playback_failure_persistence_is_serialized_off_caller_thread() -> None:
    assert "static void CCBGSetMediaFailureAsync" in SOURCE
    async_body = body("static void CCBGSetMediaFailureAsync", "static void CCBGSetMediaFailure")
    assert "CCBGEnqueueAnalyticsMutation" in async_body
    assert "CCBGSaveHealthCatalog" in async_body
    assert 'item[@"healthFailureCount"]' in async_body
    assert "CCBGRecordMediaPlaybackFailure(fileNameCopy, reasonCopy)" not in async_body
    assert "dispatch_async(dispatch_get_main_queue(), ^{ CCBGPostReload(); });" in async_body


def test_mark_failure_uses_nonblocking_path() -> None:
    mark_body = body("void CCBGMarkMediaFailure", "void CCBGClearMediaFailure")
    assert "CCBGSetMediaFailureAsync" in mark_body
    assert "CCBGSetMediaFailure(fileName" not in mark_body
    assert "CCBGPostReload" not in mark_body


if __name__ == "__main__":
    test_playback_failure_persistence_is_serialized_off_caller_thread()
    test_mark_failure_uses_nonblocking_path()
    print("Asynchronous media failure persistence checks passed")
