#!/bin/bash
# MinIO to Garage Migration Script
# Run this on your QNAP NAS after copying files to the NAS

set -e

GARAGE_IP="192.168.100.211"
GARAGE_PORT="3900"
MINIO_BUCKET="your-restic-bucket"  # UPDATE THIS
GARAGE_BUCKET="restic-backups"

echo "=========================================="
echo "MinIO to Garage Migration"
echo "=========================================="

case "${1:-help}" in
  1|setup)
    echo ""
    echo "Step 1: Create Garage directories"
    echo "----------------------------------"
    sudo mkdir -p /share/Data/garage/meta
    sudo mkdir -p /share/Data/garage/data
    echo "Directories created."
    echo ""
    echo "Next: Copy garage.toml and garage-docker-compose.yml to your NAS"
    echo "Then run: ./migrate.sh 2"
    ;;

  2|start)
    echo ""
    echo "Step 2: Start Garage container"
    echo "------------------------------"
    docker-compose -f garage-docker-compose.yml up -d
    sleep 5
    echo ""
    echo "Checking status..."
    docker exec garage /garage status || echo "Waiting for Garage to initialize..."
    echo ""
    echo "Next run: ./migrate.sh 3"
    ;;

  3|configure)
    echo ""
    echo "Step 3: Configure Garage node and create bucket"
    echo "------------------------------------------------"
    echo "Getting node ID..."
    NODE_ID=$(docker exec garage /garage status 2>/dev/null | grep -oP 'ID: \K[a-f0-9]+' | head -1)

    if [ -z "$NODE_ID" ]; then
      echo "Could not get node ID. Garage may still be initializing."
      echo "Try again in a few seconds."
      exit 1
    fi

    echo "Node ID: $NODE_ID"
    echo ""
    echo "Assigning node to layout..."
    docker exec garage /garage layout assign -z dc1 -c 1T "$NODE_ID"
    docker exec garage /garage layout apply --version 1
    echo ""
    echo "Creating access key..."
    docker exec garage /garage key create restic-key
    echo ""
    echo "IMPORTANT: Save the Key ID and Secret above!"
    echo ""
    echo "Creating bucket..."
    docker exec garage /garage bucket create "$GARAGE_BUCKET"
    docker exec garage /garage bucket allow "$GARAGE_BUCKET" --read --write --key restic-key
    echo ""
    echo "Bucket configured. Next:"
    echo "1. Update rclone.conf.template with your credentials"
    echo "2. Copy to ~/.config/rclone/rclone.conf"
    echo "3. Run: ./migrate.sh 4"
    ;;

  4|verify-source)
    echo ""
    echo "Step 4: Verify source data in MinIO"
    echo "------------------------------------"
    echo "Listing MinIO buckets..."
    rclone lsd minio:
    echo ""
    echo "Checking size of bucket to migrate..."
    rclone size "minio:$MINIO_BUCKET"
    echo ""
    echo "If this looks correct, run: ./migrate.sh 5"
    ;;

  5|migrate)
    echo ""
    echo "Step 5: Migrate data from MinIO to Garage"
    echo "------------------------------------------"
    echo "Starting migration (this may take a while)..."
    echo ""
    echo "Dry run first..."
    rclone sync "minio:$MINIO_BUCKET" "garage:$GARAGE_BUCKET" --dry-run -P
    echo ""
    read -p "Proceed with actual migration? (y/n) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
      rclone sync "minio:$MINIO_BUCKET" "garage:$GARAGE_BUCKET" -P --transfers 4
      echo ""
      echo "Migration complete! Run: ./migrate.sh 6"
    fi
    ;;

  6|verify)
    echo ""
    echo "Step 6: Verify migration with Restic"
    echo "-------------------------------------"
    echo "Source restic-env.sh first, then run these commands:"
    echo ""
    echo "  source restic-env.sh"
    echo "  restic check"
    echo "  restic snapshots"
    echo ""
    echo "If all snapshots appear and check passes, migration is successful!"
    echo "Update your backup scripts to use the new Garage endpoint."
    ;;

  *)
    echo ""
    echo "Usage: ./migrate.sh <step>"
    echo ""
    echo "Steps:"
    echo "  1 or setup         - Create Garage directories"
    echo "  2 or start         - Start Garage container"
    echo "  3 or configure     - Configure node, create bucket and key"
    echo "  4 or verify-source - Verify MinIO source data"
    echo "  5 or migrate       - Migrate data with rclone"
    echo "  6 or verify        - Verify with Restic"
    echo ""
    ;;
esac
