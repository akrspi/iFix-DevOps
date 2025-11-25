#!/bin/bash

set -e

# Variables
AWS_REGION="ap-south-1"                # Set your AWS region
AWS_PROFILE="mgramseva"              # Specify the AWS CLI profile to use
CLUSTER_NAME="mgramseva-prod"            # Set your cluster name

# Step 0: Check if AWS CLI Profile Exists
echo "Checking AWS CLI profile configuration..."
if ! aws configure list --profile $AWS_PROFILE > /dev/null 2>&1; then
    echo "AWS profile '$AWS_PROFILE' not configured. Please configure it using 'aws configure --profile $AWS_PROFILE'."
    exit 1
fi
echo "Using AWS profile: $AWS_PROFILE"

# Function to create snapshots
create_snapshot() {
    local volume_id=$1
    local description=$2
    echo "Creating snapshot for Volume ID: $volume_id"
    SNAPSHOT_ID=$(aws ec2 create-snapshot \
        --volume-id "$volume_id" \
        --description "$description" \
        --region "$AWS_REGION" \
        --profile "$AWS_PROFILE" \
        --query "SnapshotId" --output text)
    echo "Snapshot ID: $SNAPSHOT_ID"
    # Wait for the snapshot to complete
    echo "Waiting for snapshot $SNAPSHOT_ID to complete..."
    # aws ec2 wait snapshot-completed --snapshot-ids $SNAPSHOT_ID --profile $AWS_PROFILE
    echo "Snapshot $SNAPSHOT_ID completed successfully."
}

# Step 1: Fetch all volume IDs from the EKS cluster
echo "Fetching volume IDs from EKS cluster: $CLUSTER_NAME"
VOLUME_IDS=$(kubectl get pv -o jsonpath='{.items[*].spec.csi.volumeHandle}' | tr ' ' '\n')

if [ -z "$VOLUME_IDS" ]; then
    echo "No volumes found in the EKS cluster."
    exit 1
fi

# Step 2: Process and clean up volume IDs
CLEANED_VOLUME_IDS=()
for volume in $VOLUME_IDS; do
    # Extract only the volume ID (e.g., vol-XXXXXX)
    CLEANED_VOLUME_ID=$(echo "$volume" | sed -E 's|aws://[^/]+/||')
    echo $CLEANED_VOLUME_ID
    CLEANED_VOLUME_IDS+=("$CLEANED_VOLUME_ID")
done

# Step 3: Loop through each cleaned volume ID and create a snapshot
for volume_id in "${CLEANED_VOLUME_IDS[@]}"; do
    # Create a unique description for the snapshot
    DESCRIPTION="Snapshot for volume $volume_id from cluster $CLUSTER_NAME on $(date +'%Y-%m-%d %H:%M:%S') before upgrading to eks 1.32"
    create_snapshot "$volume_id" "$DESCRIPTION"
done

echo "Snapshot creation process completed."