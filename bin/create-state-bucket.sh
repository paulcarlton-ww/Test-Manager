# read parameters for shell script
#
# Usage: create_state_bucket.sh <bucket_name> <region> <prefix>
#
# Example:
#   create_state_bucket.sh my-state-bucket us-east-1 my-prefix


BUCKET_NAME=$1
REGION=$2
PREFIX=$3

if [ -z "$BUCKET_NAME" ] || [ -z "$REGION" ] || [ -z "$PREFIX" ]; then
    echo "Usage: create_state_bucket.sh <bucket_name> <region> <prefix>"
    exit 1
fi

# Create s3 bucket if it does not exist
if [ ! -z "$(aws s3 ls s3://$BUCKET_NAME 2>/dev/null)" ]; then
    echo "Bucket already exists"
else
    # Create s3 bucket for region
    echo "Creating bucket: $BUCKET_NAME"
    aws s3 mb s3://$BUCKET_NAME --region $REGION
fi

# Create prefix if it does not exist
if [ ! -z "$(aws s3 ls s3://$BUCKET_NAME/$PREFIX 2>/dev/null)" ]; then
    echo "Prefix already exists"
else
    # Create s3 prefix for region
    echo "Creating prefix: $PREFIX"
    mkdir -p $PREFIX
    aws s3 cp --recursive $PREFIX s3://$BUCKET_NAME --region $REGION
    rm -rf $PREFIX
fi

# pulumi login s3://$BUCKET_NAME/$PREFIX