# ============================================================================
# Phase 2: Automated Threat Remediation Lambda Function
# ============================================================================

# IAM Role for Lambda Function
resource "aws_iam_role" "lambda_remediation_role" {
  name = "threat-remediation-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
}

# IAM Policy for Lambda to create Network ACL entries
resource "aws_iam_role_policy" "lambda_nacl_policy" {
  name = "lambda-nacl-remediation-policy"
  role = aws_iam_role.lambda_remediation_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ec2:CreateNetworkAclEntry",
          "ec2:DeleteNetworkAclEntry",    # ← ADD THIS
          "ec2:DescribeNetworkAcls"       # ← ADD THIS (useful for debugging)
        ]
        Resource = "*"
      }
    ]
  })
}

# Archive the Lambda function Python code
data "archive_file" "lambda_remediation_zip" {
  type        = "zip"
  source_file = "${path.module}/remediation/lambda_function.py"
  output_path = "${path.module}/lambda_remediation.zip"
}

# Lambda Function for automated threat remediation
resource "aws_lambda_function" "threat_remediation" {
  filename      = data.archive_file.lambda_remediation_zip.output_path
  function_name = "threat-remediation-lambda"
  role          = aws_iam_role.lambda_remediation_role.arn
  handler       = "lambda_function.lambda_handler"
  runtime       = "python3.10"
  timeout       = 30

  source_code_hash = data.archive_file.lambda_remediation_zip.output_base64sha256

environment {
    variables = {
      NACL_ID = "acl-079be63c9236ff48b"
    }
  }

  depends_on = [
    aws_iam_role_policy.lambda_nacl_policy
  ]
}

# Lambda Function URL for Splunk webhook
resource "aws_lambda_function_url" "threat_remediation_url" {
  function_name          = aws_lambda_function.threat_remediation.function_name
  authorization_type    = "NONE"
  cors {
    allow_origins = ["*"]
    allow_methods = ["POST", "GET"]
    allow_headers = ["Content-Type", "X-Amz-Date", "Authorization"]
  }
}

# ============================================================================
# Outputs
# ============================================================================

output "lambda_function_url" {
  value       = aws_lambda_function_url.threat_remediation_url.function_url
  description = "Lambda Function URL for Splunk webhook - Use this in Splunk alert action"
}

output "lambda_function_arn" {
  value       = aws_lambda_function.threat_remediation.arn
  description = "ARN of the threat remediation Lambda function"
}

output "lambda_role_arn" {
  value       = aws_iam_role.lambda_remediation_role.arn
  description = "ARN of the Lambda execution role"
}
resource "aws_iam_role_policy_attachment" "lambda_logs" {
  role       = aws_iam_role.lambda_remediation_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}
resource "aws_lambda_permission" "allow_public_url" {
  statement_id           = "AllowPublicInvoke"
  action                 = "lambda:InvokeFunctionUrl"
  function_name          = aws_lambda_function.threat_remediation.function_name
  principal              = "*"
  function_url_auth_type = "NONE"
}