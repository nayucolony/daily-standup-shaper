  ./scripts/sync-help-to-readme.sh --update-recommended-sequence-snapshot
  ./scripts/sync-help-to-readme.sh --update-sync-line-snapshot
  ./scripts/sync-help-to-readme.sh --update-summary-line-snapshot
  ./scripts/selfcheck.sh --summary
  ./scripts/sync-help-to-readme.sh --update-one-line-contract-test-links
  ./scripts/sync-help-to-readme.sh --update-help-examples-snapshot
  ./scripts/sync-help-to-readme.sh --update-sync-help-optional-order-snapshot
  ./scripts/sync-help-to-readme.sh --all
  # retry: ./scripts/sync-help-to-readme.sh --all
  # diff: git diff -- README.md tests/snapshots
