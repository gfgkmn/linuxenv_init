#!/bin/bash
# Usage: bash wandb_info.sh [wandb_dir]
# Default: looks for ./wandb in current directory

WANDB_DIR="${1:-./wandb}"

if [ ! -d "$WANDB_DIR" ]; then
    echo "Error: wandb directory not found at $WANDB_DIR"
    echo "Usage: bash wandb_info.sh [path/to/wandb]"
    exit 1
fi

for RUN_DIR in "$WANDB_DIR"/run-*; do
    [ -d "$RUN_DIR" ] || continue

    DEBUG_LOG="$RUN_DIR/logs/debug.log"
    META_FILE="$RUN_DIR/files/wandb-metadata.json"

    # Extract run ID and date from directory name: run-YYYYMMDD_HHMMSS-RUNID
    DIR_NAME=$(basename "$RUN_DIR")
    RUN_DATE=$(echo "$DIR_NAME" | grep -oP 'run-\K\d{8}' | sed 's/\(....\)\(..\)\(..\)/\1-\2-\3/')
    RUN_ID=$(echo "$DIR_NAME" | grep -oP 'run-\d{8}_\d{6}-\K\w+')

    # Extract from debug.log
    PROJECT_NAME=""
    EXPERIMENT_NAME=""
    LOGGERS=""
    if [ -f "$DEBUG_LOG" ]; then
        PROJECT_NAME=$(grep -oP "'project_name': '\K[^']*" "$DEBUG_LOG" | head -1)
        EXPERIMENT_NAME=$(grep -oP "'experiment_name': '\K[^']*" "$DEBUG_LOG" | head -1)
        LOGGERS=$(grep -oP "'logger': \K\[[^]]*\]" "$DEBUG_LOG" | head -1 | tr -d "[]'" | sed 's/, / + /g')
    fi

    # Extract from metadata
    EMAIL=""
    if [ -f "$META_FILE" ]; then
        EMAIL=$(python -c "import json; print(json.load(open('$META_FILE')).get('email','N/A'))" 2>/dev/null)
    fi

    USERNAME=$(echo "$EMAIL" | cut -d@ -f1)

    echo "============================================"
    echo "  wandb Run Info"
    echo "============================================"
    echo "  Project name:    $PROJECT_NAME"
    echo "  Experiment name: $EXPERIMENT_NAME"
    echo "  Run ID:          $RUN_ID"
    echo "  Run date:        $RUN_DATE"
    echo "  Loggers:         $LOGGERS"
    echo "  Email:           $EMAIL"
    echo ""
    echo "  wandb URL:"
    echo "    https://wandb.ai/$USERNAME/$PROJECT_NAME"
    echo ""
    echo "  Specific run:"
    echo "    https://wandb.ai/$USERNAME/$PROJECT_NAME/runs/$RUN_ID"
    echo ""
    echo "  Trainer config:"
    echo "    trainer.project_name:    $PROJECT_NAME"
    echo "    trainer.experiment_name: $EXPERIMENT_NAME"
    echo "============================================"
    echo ""
done
