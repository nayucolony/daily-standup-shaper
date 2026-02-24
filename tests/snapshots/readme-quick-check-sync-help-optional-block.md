# 必要時のみ: 個別同期（推奨順で実行）
./scripts/sync-help-to-readme.sh --update-sync-help-optional-order-snapshot
./scripts/sync-help-to-readme.sh --update-recommended-sequence-snapshot
./scripts/sync-help-to-readme.sh --update-sync-line-snapshot
./scripts/sync-help-to-readme.sh --update-summary-line-snapshot
./scripts/sync-help-to-readme.sh --update-one-line-contract-test-links
./scripts/sync-help-to-readme.sh --update-help-examples-snapshot
