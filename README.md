# Enterprise DevSecOps Threat Pipeline

## Project Overview

This project demonstrates an enterprise-grade security operations workflow by provisioning a vulnerable AWS infrastructure entirely through Infrastructure as Code (Terraform) and implementing automated threat detection and response capabilities. The infrastructure intentionally exposes critical resources—a VPC with EC2 instances and an accessible RDS PostgreSQL database—to simulate a realistic attack environment for security research and DevSecOps validation.

## Architecture & Workflow

### Phase 1: Infrastructure & Attack Simulation

The foundational phase establishes a distributed attack scenario to generate realistic security telemetry:

- **Vulnerable AWS Infrastructure**: Complete VPC architecture provisioned via Terraform, including:
  - EC2 instances deployed across multiple availability zones
  - Exposed RDS PostgreSQL database with weak authentication controls
  - Network configurations permitting inbound access to database ports
  - Intentionally permissive security group rules to simulate common misconfigurations

- **Distributed Attacker Node**: A specialized EC2 instance (t3.micro, x86_64 architecture) deployed in the `us-west-2` region serves as the attack origin. This simulates a geographically distributed threat actor.

- **Cryptojacking Attack Simulation**: The attacker node executes a payload simulating `xmrig.exe` cryptojacking malware, launching:
  - Brute-force attacks against the RDS database (port 5432)
  - Credential enumeration and unauthorized access attempts
  - Outbound connections to cryptocurrency mining pools
  - Tens of thousands of malicious network requests sustained over the attack duration

- **Attack Traffic**: High-volume network traffic generated across multiple protocols and ports, creating realistic security events that trigger detection systems.

### Phase 2: Telemetry & Data Collection

All network and system-level activity is captured and centralized for analysis:

- **VPC Flow Logs**: Network-layer telemetry capturing:
  - Source and destination IP addresses
  - Ports and protocols for all traffic flows
  - Accept/Reject decisions at the network interface level
  - Provides foundational forensic data for attack reconstruction

- **CloudTrail Events**: API-level audit logs capturing all AWS API calls and resource modifications, including:
  - EC2 instance state changes
  - Network ACL modifications (for automated remediation tracking)
  - IAM activity and authentication events
  - Complete audit trail for compliance and forensics

- **S3 Data Lake**: Centralized repository for all telemetry data:
  - Automatically ingests VPC Flow Logs from all regions
  - Archival storage for CloudTrail events
  - Long-term retention policy for historical analysis
  - Foundation for big data analytics and machine learning applications

- **Splunk Integration**: Enterprise security analytics platform indexes all telemetry:
  - Real-time ingestion of VPC Flow Logs and CloudTrail events
  - Advanced correlation rules detect attack signatures and anomalous patterns
  - Custom detection rules identify cryptojacking behavior indicators
  - Dashboards and alerts provide security operations team visibility

### Phase 3: Automated Defense & Remediation

Upon threat detection, an automated response system executes network-layer remediation:

- **Splunk Detection Rules**: Sophisticated detection logic identifies:
  - Suspicious IP addresses with multiple failed authentication attempts
  - Anomalous port scanning activity
  - Outbound connections to known cryptocurrency mining pools
  - Traffic patterns consistent with cryptojacking campaigns

- **Alert Webhook**: Detection rules automatically trigger HTTP webhooks, sending alert payloads to a serverless Lambda function with:
  - Extracted attacker IP address
  - Attack context and severity classification
  - Timestamp and detection rule identifier

- **Lambda Remediation Function**: Serverless Python application (Boto3-powered) performs:
  - Parsing of incoming Splunk webhook alerts
  - Extraction of attacker IP addresses from alert payloads
  - Automatic AWS Network ACL rule creation
  - Immediate deny rule deployment (Rule #100)

- **Network ACL Blocking**: Instant neutralization of the threat:
  - Deny rules applied at the network perimeter (Network ACL layer)
  - All traffic from attacker IP immediately dropped
  - Remediation occurs within seconds of detection
  - Zero-trust verification: attacker cannot access any resources within the VPC
  - CloudTrail audit logs all Network ACL modifications for compliance

## Tech Stack

The project integrates enterprise-grade technologies across infrastructure, security, and automation domains:

| Category | Technologies |
|----------|--------------|
| **Infrastructure as Code** | Terraform, AWS CloudFormation (via Terraform) |
| **Cloud Platform** | AWS (EC2, RDS, VPC, Network ACL, Lambda, S3, CloudTrail, IAM) |
| **Programming Languages** | Python 3, Bash/Shell |
| **Security & Detection** | Splunk, AWS Security Hub, CloudTrail |
| **Automation & Remediation** | AWS Lambda, Boto3 (AWS SDK for Python) |
| **Operating Systems** | Amazon Linux 2023 (x86_64 architecture) |
| **Access Control** | AWS IAM (roles, policies, least-privilege permissions) |
| **Database** | PostgreSQL (RDS) |
| **Network Services** | VPC, Security Groups, Network ACLs, VPC Flow Logs |

## Repository Structure

```
enterprise-threat-pipeline/
├── README.md                   # Project documentation
├── attacker_vm.tf              # Attacker node definition (distributed us-west-2 instance)
├── compute.tf                  # Compute resources (EC2 instances)
├── iam.tf                      # IAM roles and policies
├── main.tf                     # Primary Terraform configuration
├── providers.tf                # AWS provider setup for multi-region deployment
├── variables.tf                # Input variables and defaults
├── outputs.tf                  # Terraform outputs
├── telemetry.tf                # VPC Flow Logs and data collection pipeline
├── remediation.tf              # Lambda function and Network ACL resources
├── attacker.py                 # Attack simulation script
├── remediation/
│   └── lambda_function.py      # Webhook receiver and automated remediation logic
├── .terraform/                 # Terraform state and plugins
├── .terraform.lock.hcl         # Terraform dependency lock file
└── terraform.tfstate           # Current infrastructure state
```

## Key Components

### Lambda Remediation Function (`remediation/lambda_function.py`)

Serverless Python application providing automated threat response:

- **Webhook Receiver**: Accepts HTTP POST requests from Splunk alert webhooks
- **Alert Parsing**: Extracts attacker IP address from webhook payload structure
- **AWS Integration**: Uses Boto3 to interact with AWS Network ACL APIs
- **Network ACL Rule Creation**: Automatically creates deny rules blocking attacker traffic
- **Error Handling**: Comprehensive exception handling and logging for operational visibility
- **HTTP Status Codes**: Returns appropriate response codes (200 success, 400 bad request, 500 server error) for webhook integration

### Infrastructure as Code (`remediation.tf`)

Terraform-managed resources for automated remediation:

- **IAM Execution Role**: Least-privilege role granting Lambda only `ec2:CreateNetworkAclEntry` permission
- **Code Archiving**: Automated ZIP packaging of Python function for deployment
- **Lambda Function**: Python 3.10 runtime with environment variables for NACL_ID configuration
- **Function URL**: Public HTTPS endpoint enabling Splunk webhook integration
- **Terraform Outputs**: Lambda Function URL automatically output for Splunk configuration

## Deployment

### Prerequisites

- AWS CLI configured with appropriate IAM credentials and default region
- Terraform >= 1.0 installed locally
- Python 3.10+ for local development and testing
- Valid AWS account with permissions for EC2, RDS, Lambda, IAM, and VPC resources

### Infrastructure Deployment

```bash
# Initialize Terraform (downloads providers and modules)
terraform init

# Validate configuration syntax and structure
terraform validate

# Generate deployment plan with resource preview
terraform plan -out=tfplan

# Apply infrastructure changes
terraform apply tfplan
```

### Splunk Configuration

After Terraform deployment completes:

1. Obtain the Lambda Function URL from Terraform outputs
2. Navigate to Splunk Settings → Alert Actions
3. Create a new webhook alert action with the Lambda Function URL
4. Configure detection rules to trigger the webhook upon threat detection

## Security Considerations

- **Least Privilege**: Lambda execution role has minimal permissions—only `ec2:CreateNetworkAclEntry`
- **Network Layer Defense**: Blocking occurs at Network ACL layer for maximum efficiency and lowest latency
- **Webhook Authorization**: In production environments, enable Lambda Function URL authorization (AWS_IAM)
- **Audit Trail**: All Network ACL changes logged in CloudTrail for compliance, forensics, and post-incident analysis
- **Ephemeral Rules**: Network ACL deny rules are temporary; can be manually removed via AWS Console or CLI if needed
- **Architecture Validation**: Attacker node explicitly uses x86_64 AMI to prevent compatibility issues with x86_64 instance types

## Use Cases

- **Security Research**: Understand cryptojacking attack patterns and detection methodologies
- **DevSecOps Validation**: Demonstrate automated security response in infrastructure-as-code workflows
- **Incident Response Training**: Practice threat detection and remediation workflows
- **Cloud Security**: Explore AWS security services (Network ACL, IAM, CloudTrail) in action
- **Detection Engineering**: Test and validate Splunk detection rules in a controlled environment

## Customization & Extension

The architecture supports various customization scenarios:

- **Different Threat Scenarios**: Modify attack simulation to test ransomware, data exfiltration, or privilege escalation scenarios
- **Additional Detection Rules**: Extend Splunk detection rules to identify other attack patterns
- **Multi-Region Deployment**: Terraform supports expanding to additional AWS regions
- **Enhanced Remediation**: Lambda function can be extended to trigger additional responses (EC2 termination, VPC isolation, etc.)
- **Compliance Integration**: CloudTrail events can be forwarded to compliance/audit systems

## References

- [AWS VPC Flow Logs Documentation](https://docs.aws.amazon.com/vpc/latest/userguide/flow-logs.html)
- [AWS CloudTrail User Guide](https://docs.aws.amazon.com/awscloudtrail/)
- [Terraform AWS Provider](https://registry.terraform.io/providers/hashicorp/aws/latest)
- [Boto3 EC2 Network ACL Methods](https://boto3.amazonaws.com/v1/documentation/api/latest/reference/services/ec2/client/create_network_acl_entry.html)
- [Splunk Webhook Alert Actions](https://docs.splunk.com/Documentation/Splunk/latest/Alert/Webhooks)
