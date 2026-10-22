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

    def test_macos_editor_module_is_compile_guarded(self):
        # Source-grep tests do not replace compilation, but must not *require*
        # macOS-only editor APIs in the Windows/Linux compile branches.
        mac_calls = "UnityEditor.OSXStandalone.UserBuildSettings.architecture"
        self.assertEqual(self.source.count(mac_calls), 2)
        blocks = self.source.split("#if UNITY_EDITOR_OSX")
        self.assertEqual(len(blocks) - 1, 2)
        self.assertNotIn(mac_calls, blocks[0])
        non_mac_branches = []
        for block in blocks[1:]:
            mac_branch, guard_end = block.split("#else", 1)
            self.assertIn(mac_calls, mac_branch)
            non_mac_branch, after_guard = guard_end.split("#endif", 1)
            non_mac_branches.append(non_mac_branch)
            self.assertNotIn(mac_calls, after_guard)
        # Preparation/build refuses explicitly; receipt reporting stays usable so
        # scene validation still works from a Windows/Linux Editor.
        self.assertIn("throw new InvalidOperationException", non_mac_branches[0])
        self.assertIn('return "unavailable-non-macos-editor";', non_mac_branches[1])

    def test_prepare_refuses_unsupported_target_before_mutation(self):
        prepare = self.source.split("public static void Prepare()", 1)[1].split("[MenuItem(", 1)[0]
        self.assertEqual(prepare.count("ConfigureActiveStandaloneTarget();"), 1)
        guard = prepare.index("ConfigureActiveStandaloneTarget();")
        for mutation in ("EditorSceneManager.NewScene", "EnsurePresentationPanel(scene);",
                         "EditorBuildSettings.scenes =", "PlayerSettings.companyName"):
            with self.subTest(mutation=mutation):
                self.assertLess(guard, prepare.index(mutation))

    def test_windows_and_linux_players_require_a_fresh_directory(self):
        resolve = self.source.split("private static string ResolveBuildOutput(", 1)[1].split("private static void ValidateBuiltArtifact(", 1)[0]
        self.assertIn("bool selfContainedBundle = target == BuildTarget.StandaloneOSX;", resolve)
        self.assertIn('Path.Combine(EvidenceRoot, target + "-" + DateTime.UtcNow.ToString("yyyyMMdd-HHmmss"),', resolve)
        self.assertIn("if (!selfContainedBundle)", resolve)
        self.assertIn("string.Equals(playerDirectory + Path.DirectorySeparatorChar, evidenceRoot, comparison)", resolve)
        self.assertIn("|| Directory.Exists(playerDirectory)", resolve)

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
