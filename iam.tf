# Create the IAM User for Kenny
resource "aws_iam_user" "splunk_reader" {
  name = "splunk-reader"
}

# Grant Read-Only access to the specific Log Bucket
resource "aws_iam_policy" "splunk_read_policy" {
  name        = "SplunkS3ReadOnly"
  description = "Allows Splunk to ingest logs from the threat-pipeline S3 bucket"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ListAllBuckets"
        Action = ["s3:ListAllMyBuckets"]
        Effect = "Allow"
        Resource = "*"
      },
      {
        Sid    = "ReadSpecificBucket"
        Action = ["s3:Get*", "s3:List*"]
        Effect = "Allow"
        Resource = [
          aws_s3_bucket.log_bucket.arn,
          "${aws_s3_bucket.log_bucket.arn}/*"
        ]
      }
    ]
  })
}

# Attach the policy to the user
resource "aws_iam_user_policy_attachment" "attach_policy" {
  user       = aws_iam_user.splunk_reader.name
  policy_arn = aws_iam_policy.splunk_read_policy.arn
}