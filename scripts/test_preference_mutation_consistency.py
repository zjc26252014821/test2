from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SOURCE = (ROOT / "shared" / "CCBGMediaCatalog.m").read_text(encoding="utf-8")


def function_body(signature: str, next_signature: str) -> str:
    return SOURCE.split(signature, 1)[1].split(next_signature, 1)[0]


# These maintenance operations write the shared preference domain directly
# because they remove arbitrary nested references. They must still serialize
# with normal writes and invalidate the App-side preference snapshot.
for signature, next_signature in (
    ("void CCBGRemoveMediaConfigurationFromAllModules", "void CCBGRemoveAllMediaConfigurations"),
    ("void CCBGRemoveAllMediaConfigurations", "void CCBGPruneMissingMediaConfigurations"),
    ("void CCBGPruneMissingMediaConfigurations", "NSArray<NSDictionary *> *CCBGLoadMediaCatalog"),
):
    body = function_body(signature, next_signature)
    assert "CCBGWithFileLock(CCBGPreferencesMutationLockPath" in body, signature
    assert "CCBGInvalidatePreferenceReadCache();" in body, signature

migration = function_body(
    "void CCBGMigrateLegacyAutomationPreferences",
    "static NSDictionary<NSString *, id> *CCBGDarkAppearanceLastDiagnostics",
)
assert "CCBGInvalidatePreferenceReadCache();" in migration, "legacy migration"
assert "CCBGWithFileLock(CCBGPreferencesMutationLockPath" in migration, "legacy migration lock"

print("Preference mutation consistency checks passed")
