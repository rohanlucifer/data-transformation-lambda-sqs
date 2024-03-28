# Creating S3 bucket
resource "aws_s3_bucket" "ingesting-bucket" {
  bucket = "f-b-ingest-bucket"
  acl    = "private"

  tags = {
    Environment = "f-b-test"
  }
}

# Creating Lambda IAM resource
resource "aws_iam_role" "lambda_iam" {
  name = "f-b-lambda-role"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "lambda.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
}

resource "aws_iam_role_policy" "lambda_iam_policy" {
  name = "lambda-f-b-policy"
  role = aws_iam_role.lambda_iam.id

  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": [
        "s3:*",
        "sqs:*",
        "dynamodb:*"
      ],
      "Effect": "Allow",
      "Resource": "*"
    }
  ]
}
EOF
}

# Creating Lambda resource
resource "aws_lambda_function" "data_transformation_lambda" {
  function_name    = "f-b-lambda-function"
  role             = aws_iam_role.lambda_iam.arn
  handler          = "src/${var.handler_name}.lambda_handler"
  runtime          = "python3.12"
  timeout          = 60
  filename         = "../src.zip"
  source_code_hash = filebase64sha256("../src.zip")
  environment {
    variables = {
      env            = "f-b-test"
      S3_BUCKET_NAME  = aws_s3_bucket.ingesting-bucket.bucket
      DYNAMODB_TABLE  = aws_dynamodb_table.transformed_data_table.name
    }
  }
}

# Creating SQS resource
resource "aws_sqs_queue" "transformation_queue" {
  name = "f-b-sqs-queue"
}


# Creating DynamoDB table
resource "aws_dynamodb_table" "transformed_data_table" {
  name           = "f-b-dynamodb"
  billing_mode   = "PAY_PER_REQUEST"
  hash_key       = "id"
  attribute {
    name = "id"
    type = "S"
  }
}




# Granting Lambda permission to access S3 bucket for ingestion
resource "aws_lambda_permission" "s3_ingest_permission" {
  statement_id  = "AllowS3Invoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.data_transformation_lambda.function_name
  principal     = "s3.amazonaws.com"
  source_arn    = aws_s3_bucket.ingesting-bucket.arn
}

# Granting Lambda permission to access SQS queue for receiving transformation requests
resource "aws_lambda_permission" "sqs_permission" {
  statement_id  = "AllowSQSInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.data_transformation_lambda.function_name
  principal     = "sqs.amazonaws.com"
  source_arn    = aws_sqs_queue.transformation_queue.arn
}

# Configuring S3 bucket notification to trigger Lambda function on new object creation
resource "aws_s3_bucket_notification" "lambda_trigger" {
  bucket = aws_s3_bucket.ingesting-bucket.id

  lambda_function {
    lambda_function_arn = aws_lambda_function.data_transformation_lambda.arn
    events              = ["s3:ObjectCreated:*"]
  }
}
