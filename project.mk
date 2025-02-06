PROJECT_NAME := platform-ref-gcp
UPTEST_INPUT_MANIFESTS := examples/cluster-claim.yaml,examples/mysql-claim.yaml,examples/app-claim.yaml
UPTEST_SKIP_IMPORT := true
UPTEST_SKIP_UPDATE := true
UPTEST_DEFAULT_TIMEOUT = 3600s
