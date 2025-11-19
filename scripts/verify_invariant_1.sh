#!/bin/bash
# Script: verify_invariant_1.sh
# Purpose: Automated regression testing for Heimdall Invariant 1
# Usage: ./scripts/verify_invariant_1.sh

REGION="us-east-1"
REPO="heimdall-gateway"
ACCOUNT="243102737465"
REGISTRY="${ACCOUNT}.dkr.ecr.${REGION}.amazonaws.com"

echo "🔍 Finding latest RUNNABLE SIGNED image..."

# ROBUST METHOD: Get all tags -> Split lines -> Filter out .sig/.att -> Take the last one
LATEST_TAG=$(aws ecr describe-images \
    --repository-name $REPO \
    --region $REGION \
    --query 'sort_by(imageDetails, &imagePushedAt)[*].imageTags[*]' \
    --output text \
    | tr '\t' '\n' \
    | grep -v "\.sig" \
    | grep -v "\.att" \
    | tail -n 1)

if [ -z "$LATEST_TAG" ] || [ "$LATEST_TAG" == "None" ]; then
    echo "❌ ERROR: Could not find a runnable image. Raw output was empty."
    exit 1
fi

echo "   Target: $LATEST_TAG"

echo "🧹 Cleaning up battlefield..."
kubectl delete pod friend foe --ignore-not-found=true --wait=true > /dev/null 2>&1

echo "----------------------------------------"
echo "🧪 TEST A: FRIEND (Signed + SBOM)"
echo "----------------------------------------"
kubectl run friend --image=$REGISTRY/$REPO:$LATEST_TAG
if [ $? -eq 0 ]; then
    echo "✅ [PASS] Friend admitted."
else
    echo "❌ [FAIL] Friend blocked! Check your keys."
fi

echo "----------------------------------------"
echo "🧪 TEST B: FOE (Unsigned / Old)"
echo "----------------------------------------"
# Uses a known bad hash
kubectl run foe --image=$REGISTRY/$REPO:5f3ec204e798bef3b78e63c3bc2bdabcc60022e1
if [ $? -ne 0 ]; then
    echo "✅ [PASS] Foe blocked."
else
    echo "❌ [FAIL] Foe snuck in! Policy is broken."
fi