#!/bin/zsh
set -euo pipefail
cd "${0:A:h}"
TEST_DIR=$(mktemp -d)
trap 'rm -rf "$TEST_DIR"' EXIT
swiftc -parse-as-library Sources/Core.swift Tests/CoreTests.swift -o "$TEST_DIR/CoreTests"
"$TEST_DIR/CoreTests" --live
swiftc -parse-as-library Sources/Core.swift Sources/YGO.swift Tests/YGOTests.swift -o "$TEST_DIR/YGOTests"
"$TEST_DIR/YGOTests"
swiftc -parse-as-library Sources/Core.swift Sources/Collection.swift Tests/CollectionTests.swift -o "$TEST_DIR/CollectionTests"
if [[ "${1:-}" == "--skip-pricing-live" ]]; then
  "$TEST_DIR/CollectionTests"
else
  "$TEST_DIR/CollectionTests" --live
fi

swiftc -parse-as-library Sources/Core.swift Sources/YGO.swift Sources/Collection.swift Sources/RuleData.swift Sources/WorkshopCore.swift Tests/WorkshopTests.swift -o "$TEST_DIR/WorkshopTests"
"$TEST_DIR/WorkshopTests"

swiftc -parse-as-library Sources/Core.swift Sources/YGO.swift Sources/Collection.swift Sources/RuleData.swift Sources/WorkshopCore.swift Sources/LabCore.swift Sources/ProbabilityCore.swift Tests/LabTests.swift -o "$TEST_DIR/LabTests"
"$TEST_DIR/LabTests"

swiftc -parse-as-library Sources/Core.swift Sources/YGO.swift Sources/Collection.swift Sources/RuleData.swift Sources/WorkshopCore.swift Sources/LabCore.swift Sources/ProbabilityCore.swift Sources/AdvancedCore.swift Tests/AdvancedTests.swift -o "$TEST_DIR/AdvancedTests"
"$TEST_DIR/AdvancedTests"

swiftc -whole-module-optimization -D TESTING -parse-as-library Sources/*.swift Tests/RecoveryTests.swift -o "$TEST_DIR/RecoveryTests"
"$TEST_DIR/RecoveryTests"

swiftc -whole-module-optimization -D TESTING -parse-as-library Sources/*.swift Tests/FeatureTests.swift -o "$TEST_DIR/FeatureTests"
"$TEST_DIR/FeatureTests"

swiftc -parse-as-library Sources/Core.swift Sources/Collection.swift Tests/PricingReliabilityTests.swift -o "$TEST_DIR/PricingReliabilityTests"
"$TEST_DIR/PricingReliabilityTests"
