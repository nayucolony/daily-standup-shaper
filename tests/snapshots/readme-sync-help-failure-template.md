retry: ./scripts/sync-help-to-readme.sh --all
diff: git diff -- README.md tests/snapshots
