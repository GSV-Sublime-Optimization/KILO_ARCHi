"""Source contract for ARCHi's explicitly qualified Unity standalone build helper."""

from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]
BUILD = ROOT / "unity" / "ARCHi" / "Assets" / "ARCHi" / "Editor" / "ARCHiPortBuild.cs"


class UnityPortabilitySourceTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.source = BUILD.read_text(encoding="utf-8")

    def test_declares_three_explicit_standalone_targets(self):
        expected = {
            'BuildStandalone(BuildTarget.StandaloneOSX, ".app", "MAC_ARM64"': "macOS",
            'BuildStandalone(BuildTarget.StandaloneWindows64, ".exe", "WINDOWS_X64"': "Windows",
            'BuildStandalone(BuildTarget.StandaloneLinux64, ".x86_64", "LINUX_X64"': "Linux",
        }
        for needle, platform in expected.items():
            with self.subTest(platform=platform):
                self.assertIn(needle, self.source)
    def test_build_refuses_target_or_module_mismatch(self):
        self.assertIn("EditorUserBuildSettings.activeBuildTarget != target", self.source)
        self.assertIn("BuildPipeline.IsBuildTargetSupported(BuildTargetGroup.Standalone, target)", self.source)
        self.assertNotIn("SwitchActiveBuildTarget", self.source)

    def test_prepare_configures_only_supported_standalone_targets(self):
        self.assertIn("ConfigureActiveStandaloneTarget();", self.source)
        self.assertIn("case BuildTarget.StandaloneOSX:", self.source)
        self.assertIn("case BuildTarget.StandaloneWindows64:", self.source)
        self.assertIn("case BuildTarget.StandaloneLinux64:", self.source)
        self.assertIn("OSXStandalone.UserBuildSettings.architecture = OSArchitecture.ARM64", self.source)

    def test_artifact_validation_is_platform_specific(self):
        self.assertIn('artifact.EndsWith(artifactSuffix, comparison)', self.source)
        self.assertIn('Path.Combine(artifact, "Contents", "Info.plist")', self.source)
        self.assertIn("if (!File.Exists(artifact))", self.source)
        self.assertIn("ValidateBuiltArtifact(target, artifact);", self.source)

    def test_receipt_architecture_is_not_hardcoded_to_macos(self):
        self.assertIn("architecture = ActiveArchitecture()", self.source)
        self.assertIn('return "x86_64";', self.source)
        self.assertIn("runtimeInteractionVerified = false", self.source)
    def test_build_success_requires_zero_unity_errors(self):
        self.assertIn(
            "report.summary.result == BuildResult.Succeeded && report.summary.totalErrors == 0",
            self.source,
        )

    def test_mac_bundle_metadata_remains_mac_only(self):
        self.assertIn("if (target == BuildTarget.StandaloneOSX)", self.source)
        self.assertIn("StampMacBundle(artifact);", self.source)
        self.assertEqual(self.source.count("StampMacBundle(artifact);"), 1)


if __name__ == "__main__":
    unittest.main()
