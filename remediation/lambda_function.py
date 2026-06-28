import json
import boto3
import os
import urllib.request
from botocore.exceptions import ClientError

# Target N. Virginia where your VPC actually lives
ec2_client = boto3.client('ec2', region_name='us-east-1')

def lambda_handler(event, context):
    # Print the incoming event so we can ALWAYS see it in CloudWatch
    print(f"Incoming Event: {json.dumps(event)}")
    
    try:
        # Safely parse the payload whether it comes wrapped in an HTTP 'body' or not
        if 'body' in event and event['body']:
            if isinstance(event['body'], str):
                payload = json.loads(event['body'])
            else:
                payload = event['body']
        else:
            payload = event
            
        print(f"Parsed Payload: {json.dumps(payload)}")
        
        # Extract attacker IP from Splunk alert
        attacker_ip = payload['result']['src_ip']
        print(f"Target Acquired: {attacker_ip}")
        
        # Get NACL ID from environment variables
        nacl_id = os.environ.get('NACL_ID')
        if not nacl_id:
            raise ValueError("NACL_ID environment variable is missing!")
            
        print(f"Executing Kill-Switch on NACL: {nacl_id}")
        
        # Create deny rule in Network ACL
        response = ec2_client.create_network_acl_entry(
            NetworkAclId=nacl_id,
            RuleNumber=90,
            Protocol='-1',  # All protocols
            RuleAction='deny',
            Egress=False,   # Explicitly block INBOUND traffic
            CidrBlock=f'{attacker_ip}/32'
        )
        
        print(f"SUCCESS: Rule 90 Deny injected for {attacker_ip}")
        
        # --- NEW: SECURE CHATOPS VERIFICATION ALERTS ---
        # Securely pull the URL from AWS Environment Variables
        webhook_url = os.environ.get('CHATOPS_WEBHOOK')
        
        if webhook_url:
            alert_message = {
                "content": f"🚨 **DevSecOps Auto-Remediation Triggered!** 🚨\n**Action:** Blocked Malicious IP\n**Target:** `{attacker_ip}`\n**Mechanism:** VPC Network ACL (Rule 90)\n**Status:** SUCCESS"
            }
            
            req = urllib.request.Request(
                webhook_url, 
                data=json.dumps(alert_message).encode('utf-8'), 
                headers={'Content-Type': 'application/json', 'User-Agent': 'AWS-Lambda-SecBot'}
            )
            
            try:
                urllib.request.urlopen(req)
                print("ChatOps alert sent successfully to Discord.")
            except Exception as alert_error:
                print(f"Failed to send ChatOps alert: {alert_error}")
        else:
            print("Notice: CHATOPS_WEBHOOK environment variable not set. Skipping Discord alert.")
        # --- END CHATOPS ---

        return {
            'statusCode': 200,
            'body': json.dumps({'message': f'Successfully blocked {attacker_ip}'})
        }
        
    except Exception as e:
        # Print the error so it actually shows up in red in CloudWatch!
        print(f"FATAL ERROR: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }