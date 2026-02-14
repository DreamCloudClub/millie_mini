#!/bin/bash
# Test Dream Cloud Subscription API endpoint

echo "Testing Dream Cloud Subscription API..."
echo ""

# Replace with your test email
TEST_EMAIL="your-email@example.com"

if [ "$TEST_EMAIL" == "your-email@example.com" ]; then
    echo "⚠️  Please edit this script and set TEST_EMAIL to your actual email address"
    exit 1
fi

echo "Testing with email: $TEST_EMAIL"
echo ""

curl -X POST "https://dreamcloudclub.org/wp-json/dreamcloud/v1/check-subscription" \
  -H "Content-Type: application/json" \
  -d "{\"email\": \"$TEST_EMAIL\"}" \
  -w "\n\nHTTP Status: %{http_code}\n" \
  -s

echo ""
echo ""
echo "Expected responses:"
echo "  - 200 with status 'holder' = Crypto Holder"
echo "  - 200 with status 'active' = Subscriber"
echo "  - 200 with status 'inactive' = No subscription"
echo "  - 404 = Email not found"

