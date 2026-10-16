#!/usr/bin/env python3
"""Run actual Mac workspace XCTest against a built debug app, without launching its App host.

First build PinkHouseOps with xcodebuild build-for-testing. All stores are ephemeral;
the test fixture substitutes a queue that never starts a network request.
"""
import argparse
import json
from pathlib import Path
import subprocess
import tempfile


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--derived-data", type=Path, required=True)
    snapshots = parser.add_mutually_exclusive_group()
    snapshots.add_argument("--snapshot-dir", type=Path, help="Optional directory for real SwiftUI fixture screenshots")
    snapshots.add_argument("--reservation-batch-snapshot-dir", type=Path, help="Only capture the reservation batch upload and review pages")
    args = parser.parse_args()
    repo = Path(__file__).resolve().parents[2]
    products = args.derived_data.resolve() / "Build/Products/Debug"
    app = products / "PinkHouseOps.app/Contents"
    dylib = app / "MacOS/PinkHouseOps.debug.dylib"
    if not dylib.is_file():
        parser.error("Build PinkHouseOps in Debug with build-for-testing first.")
    developer = Path(subprocess.check_output(["xcode-select", "-p"], text=True, encoding="utf-8").strip())
    platform = developer / "Platforms/MacOSX.platform/Developer"
    frameworks = products / "PackageFrameworks"
    shared = list(frameworks.glob("SharedCatalog_*.framework"))
    if len(shared) != 1:
        parser.error("Expected one built SharedCatalog package framework.")
    with tempfile.TemporaryDirectory(prefix="ops-editor-regressions-") as scratch:
        directory = Path(scratch)
        runner = directory / "Runner.swift"
        snapshot_call = ""
        if args.snapshot_dir:
            output = json.dumps(str(args.snapshot_dir.resolve()), ensure_ascii=False)
            snapshot_call = "try! OpsCatalogEditorSnapshots.run(into: URL(fileURLWithPath: " + output + "))"
        elif args.reservation_batch_snapshot_dir:
            output = json.dumps(str(args.reservation_batch_snapshot_dir.resolve()), ensure_ascii=False)
            snapshot_call = "try! OpsReservationBatchSnapshots.run(into: URL(fileURLWithPath: " + output + "))"
        runner.write_text("""import Foundation
import XCTest
@main struct Runner {
    @MainActor static func main() {
        let suite = OpsCatalogEditorPersistenceTests.defaultTestSuite
        suite.run()
        SNAPSHOT_CALL
        exit(suite.testRun?.hasSucceeded == true && suite.testCaseCount > 0 ? 0 : 1)
    }
}
""".replace("SNAPSHOT_CALL", snapshot_call), encoding="utf-8")
        binary = directory / "regressions"
        command = ["xcrun", "swiftc", "-swift-version", "5", "-parse-as-library",
                   "-target", "arm64-apple-macos26.2",
                   "-I", str(products), "-I", str(platform / "usr/lib"),
                   "-F", str(frameworks), "-F", str(platform / "Library/Frameworks"),
                   "-L", str(platform / "usr/lib"), str(dylib), "-framework", shared[0].stem]
        # 普通构建可能不再把测试包 framework 嵌入 App；独立 runner 仍从 Products 读取它。
        for path in [frameworks, app / "MacOS", app / "Frameworks", platform / "Library/Frameworks", platform / "usr/lib"]:
            command.extend(["-Xlinker", "-rpath", "-Xlinker", str(path)])
        command.extend([str(repo / "PinkHouseOpsTests/OpsCatalogEditorPersistenceTests.swift"),
                        str(runner), "-o", str(binary)])
        if args.snapshot_dir:
            command.append(str(repo / "tools/testing/OpsCatalogEditorSnapshots.swift"))
        elif args.reservation_batch_snapshot_dir:
            command.append(str(repo / "tools/testing/OpsReservationBatchSnapshots.swift"))
        subprocess.run(command, cwd=repo, check=True)
        subprocess.run([str(binary)], cwd=repo, check=True)


if __name__ == "__main__":
    main()
