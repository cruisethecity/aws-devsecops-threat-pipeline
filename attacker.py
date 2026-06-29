"""
Enterprise DevSecOps Threat Pipeline
Automated Remediation Lambda - Phase 2

Pipeline Architecture:
  Attack Script
    → VPC Flow Logs → CloudWatch → Splunk Ingestion
      → Correlation Search (Block_IPAddress_Alert)
        → Webhook → THIS LAMBDA
          → NACL Deny Rule (AWS VPC)
            → CloudWatch SUCCESS Log → Splunk Panel 1 & 4
              → Discord ChatOps Alert

Author: Keenen Wilkins (Infrastructure & Terraform) / Kenny Barr (SOC & Splunk)
Phase: 2 - Automated IP Block via Network ACL
"""

import json
import boto3
import urllib.request
import urllib.error
from botocore.exceptions import ClientError

# ---------------------------------------------------------------------------
# CONFIGURATION
# These are the environment-specific values for our AWS deployment.
# NACL_ID ties this Lambda to the specific Network ACL protecting our VPC.
# ---------------------------------------------------------------------------
NACL_ID = "acl-079be63c9236ff48b"
RULE_NUMBER = 90          # Dedicated rule slot for automated attacker blocks
DISCORD_WEBHOOK_URL = "YOUR_DISCORD_WEBHOOK_URL_HERE"  # Replace with actual URL

# Initialize the EC2 client once at cold-start, not per-invocation.
# This reduces latency on warm Lambda executions.
ec2_client = boto3.client('ec2', region_name='us-east-1')


def lambda_handler(event, context):
    """
    Entry point for all Splunk webhook invocations.

    Decision: We use a single rule number (90) and implement Delete-Before-Create
    rather than dynamic rule numbering. This keeps the architecture simple and
    ensures Panel 1/4 Splunk queries targeting "Rule 90" remain accurate.
    The Splunk-side throttle (see README) prevents simultaneous multi-IP
    invocations that would otherwise cause a delete-overwrite race condition.
    """

    print(f"Incoming Event: {json.dumps(event)}")

    # -----------------------------------------------------------------------
    # STEP 1: Parse the Splunk webhook payload
    #
    # Splunk sends the alert result as a JSON string inside the 'body' key
    # of the Lambda Function URL event. We must json.loads() it twice:
    # once for the outer Function URL wrapper, once for the inner Splunk body.
    # -----------------------------------------------------------------------
    try:
        body = json.loads(event.get('body', '{}'))
        print(f"Parsed Payload: {json.dumps(body)}")

        result  = body.get('result', {})
        src_ip  = result.get('src_ip')
        dest_port = result.get('dest_port', 'unknown')
        severity  = result.get('severity', 'unknown')

    except (json.JSONDecodeError, AttributeError) as e:
        print(f"FATAL ERROR: Payload parse failed - {e}")
        return {
            'statusCode': 400,
            'body': json.dumps('Bad payload structure')
        }

    # Guard: no valid IP means nothing to block
    if not src_ip or src_ip in ('unknown', '', None):
        print("FATAL ERROR: No valid src_ip found in payload. Aborting.")
        return {
            'statusCode': 400,
            'body': json.dumps('Missing src_ip')
        }

    print(f"Target Acquired: {src_ip}")
    print(f"Executing Kill-Switch on NACL: {NACL_ID}")

    # -----------------------------------------------------------------------
    # STEP 2: Delete-Before-Create (Idempotency Pattern)
    #
    # Problem this solves: Lambda is stateless. On every invocation it wakes
    # up fresh with no memory of prior runs. If Rule 90 already exists from
    # a previous block, CreateNetworkAclEntry throws NetworkAclEntryAlreadyExists
    # and the function crashes with a 500.
    #
    # Fix: Attempt to delete Rule 90 first. If it doesn't exist, the ClientError
    # is caught silently and we proceed to create. If it does exist, we clear it,
    # then create fresh. Either path leads to a clean write.
    #
    # Important: This is why Splunk throttling matters. If two Lambda invocations
    # run within milliseconds of each other for different IPs, one delete can wipe
    # the other's create. The Splunk-side 10-minute throttle per src_ip prevents
    # this race condition by ensuring only one invocation runs at a time.
    # -----------------------------------------------------------------------
    try:
        ec2_client.delete_network_acl_entry(
            NetworkAclId=NACL_ID,
            Egress=False,
            RuleNumber=RULE_NUMBER
        )
        print(f"Existing Rule {RULE_NUMBER} cleared. Lane is open for re-injection.")

    except ClientError as e:
        error_code = e.response['Error']['Code']
        # InvalidNetworkAclEntry.NotFound = rule didn't exist, that's fine
        # Any other ClientError = log it but don't abort, let create attempt run
        print(f"Delete step note ({error_code}): No existing rule to clear.")

    # -----------------------------------------------------------------------
    # STEP 3: Inject the NACL Deny Rule
    #
    # Protocol '-1' = All traffic (ICMP, TCP, UDP).
    # We block all protocols from this IP, not just the port they attacked on,
    # because an attacker who owned 5432 may pivot to other ports immediately.
    # CidrBlock /32 = exact host match, no collateral damage to adjacent IPs.
    # -----------------------------------------------------------------------
    try:
        ec2_client.create_network_acl_entry(
            NetworkAclId=NACL_ID,
            RuleNumber=RULE_NUMBER,
            Protocol='-1',
            RuleAction='deny',
            Egress=False,
            CidrBlock=f"{src_ip}/32"
        )

        # CRITICAL: This exact string is what Panel 1 counts and Panel 4 lists.
        # Do not alter this print statement without updating the Splunk SPL queries.
        print(f"SUCCESS: Rule 90 Deny injected for {src_ip}")

    except ClientError as e:
        # If we still hit AlreadyExists here, a truly concurrent invocation
        # won a race condition. Log it and return 200 to prevent Splunk
        # from retrying infinitely - the IP is already blocked.
        error_code = e.response['Error']['Code']
        if error_code == 'NetworkAclEntryAlreadyExists':
            print(f"INFO: Rule 90 already active (concurrent invocation won race). "
                  f"{src_ip} is blocked. Returning 200.")
            return {
                'statusCode': 200,
                'body': json.dumps(f'{src_ip} already blocked by concurrent invocation')
            }
        # Any other AWS error (permissions, invalid NACL ID, etc.)
        print(f"FATAL ERROR: {e}")
        return {
            'statusCode': 500,
            'body': json.dumps(f'NACL injection failed: {str(e)}')
        }

    # -----------------------------------------------------------------------
    # STEP 4: ChatOps Discord Alert
    #
    # Non-critical path: if Discord is down or the URL is wrong, we do NOT
    # want to crash the Lambda or roll back the NACL block. The IP is already
    # blocked at this point. Discord failure is logged but doesn't affect the
    # 200 return or the CloudWatch SUCCESS string above.
    # -----------------------------------------------------------------------
    try:
        discord_payload = {
            "content": (
                f"🚨 **THREAT NEUTRALIZED** 🚨\n"
                f"**Attacker IP:** `{src_ip}`\n"
                f"**Port Targeted:** `{dest_port}`\n"
                f"**Severity:** `{severity}`\n"
                f"**Action:** NACL Rule {RULE_NUMBER} Deny injected\n"
                f"**Pipeline:** Splunk → Lambda → NACL ✅"
            )
        }
        data = json.dumps(discord_payload).encode('utf-8')
        req = urllib.request.Request(
            DISCORD_WEBHOOK_URL,
            data=data,
            headers={'Content-Type': 'application/json'},
            method='POST'
        )
        urllib.request.urlopen(req, timeout=5)
        print("ChatOps alert sent successfully to Discord.")

    except (urllib.error.URLError, Exception) as e:
        print(f"Discord alert failed (non-critical, block still active): {e}")

    # -----------------------------------------------------------------------
    # Return 200 to Splunk. This signals the webhook action completed cleanly.
    # Splunk uses this response code to mark the alert action as "succeeded"
    # in index=_internal logs.
    # -----------------------------------------------------------------------
    return {
        'statusCode': 200,
        'body': json.dumps(f'SUCCESS: {src_ip} blocked at Rule {RULE_NUMBER}')
    }
