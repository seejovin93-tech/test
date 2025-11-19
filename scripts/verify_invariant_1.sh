#!/bin/bash
# Script: verify_invariant_1.sh
# Purpose: Automated regression testing for Heimdall Invariant 1 (Provenance & Signing)

REGION="us-east-1"
REPO="heimdall-gateway"
ACCOUNT="243102737465"
REGISTRY="${ACCOUNT}.dkr.ecr.${REGION}.amazonaws.com"

echo "🔍 Finding latest SIGNED image..."
LATEST_TAG=$(aws ecr describe-images --repository-name $REPO --region $REGION --query 'sort_by(imageDetails, &imagePushedAt)[-1].imageTags[0]' --output text)
echo "   Target: $LATEST_TAG"

echo "🧹 Cleaning up old tests..."
kubectl delete pod friend foe --ignore-not-found=true --wait=true > /dev/null

echo "🚀 Launching FRIEND (Expect: Created)..."
kubectl run friend --image=$REGISTRY/$REPO:$LATEST_TAG
RES_FRIEND=$?

echo "🛡️ Launching FOE (Expect: Error/Blocked)..."
# We use a hardcoded old unsigned hash or public image
kubectl run foe --image=$REGISTRY/$REPO:5f3ec204e798bef3b78e63c3bc2bdabcc60022e1
RES_FOE=$?

echo "----------------------------------------"
echo "📊 INVARIANT 1 REPORT CARD"
echo "----------------------------------------"

if [ $RES_FRIEND -eq 0 ]; then
    echo "✅ [PASS] Signed Image: ALLOWED"
else
    echo "❌ [FAIL] Signed Image: BLOCKED (Check Policy/Signature)"
fi

if [ $RES_FOE -ne 0 ]; then
    echo "✅ [PASS] Unsigned Image: BLOCKED"
else
    echo "❌ [FAIL] Unsigned Image: ALLOWED (Policy is broken!)"
fi