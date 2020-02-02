# https://www.terraform.io/downloads.html

provider "aws" {
    region = "eu-west-2"
}

#########################################
#
# S3 bucket for receiving new data inputs
#
#########################################

resource "random_id" "chaos_stack" {
  byte_length = 8
}

resource "aws_s3_bucket" "chaos_bucket" {
  bucket = "chaos-bucket-${random_id.chaos_stack.hex}"
}

resource "aws_s3_bucket_notification" "bucket_notification" {
  bucket = "${aws_s3_bucket.chaos_bucket.id}"

  lambda_function {
    lambda_function_arn = "${aws_lambda_function.chaos_lambda.arn}"
    events              = ["s3:ObjectCreated:*"]
    filter_prefix       = "input/"
    filter_suffix       = ".json"
  }
}

#########################################
#
# Chaos-prepared Lambda function
#
#########################################

resource "aws_iam_role" "chaos_lambda_role" {
  name = "ChaosLambdaRole"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "lambda.amazonaws.com"
      },
      "Effect": "Allow"
    }
  ]
}
EOF
}

resource "aws_iam_role_policy" "chaos_policy" {
  name = "ChaosLambdaPermissions"
  role = aws_iam_role.chaos_lambda_role.id

  policy = <<-EOF
  {
    "Version": "2012-10-17",
    "Statement": [
      {
        "Action": [
          "ssm:GetParameter"
        ],
        "Effect": "Allow",
        "Resource": "${aws_ssm_parameter.chaos_lambda_param.arn}"
      },
      {
        "Action": [
          "s3:GetObject",
          "s3:PutObject"
        ],
        "Effect": "Allow",
        "Resource": "${aws_s3_bucket.chaos_bucket.arn}/*"
      },
      {
        "Action": [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ],
        "Effect": "Allow",
        "Resource": "*"
      }
    ]
  }
  EOF
}

resource "aws_lambda_permission" "allow_bucket" {
  statement_id  = "AllowExecutionFromS3Bucket"
  action        = "lambda:InvokeFunction"
  function_name = "${aws_lambda_function.chaos_lambda.arn}"
  principal     = "s3.amazonaws.com"
  source_arn    = "${aws_s3_bucket.chaos_bucket.arn}"
}

data "archive_file" "chaos_lambda_zip" {
  source_dir  = "${path.module}/src/"
  output_path = "${path.module}/build/chaos_lambda.zip"
  type        = "zip"
}

resource "aws_lambda_function" "chaos_lambda" {
    filename = "build/chaos_lambda.zip"
    source_code_hash = filebase64sha256("build/chaos_lambda.zip")
    function_name = "ChaosTransformer-${random_id.chaos_stack.hex}"
    handler = "lambda.handler"
    memory_size = 128
    role = aws_iam_role.chaos_lambda_role.arn
    runtime = "nodejs12.x"
    timeout = 3
    environment {
        variables = {
            FAILURE_INJECTION_PARAM = "failureLambdaConfig"
        }
    }

    tracing_config {
        mode = "PassThrough"
    }

}

#########################################
#
# Chaos Lambda configuration parameter
#
#########################################

resource "aws_ssm_parameter" "chaos_lambda_param" {
  name  = "failureLambdaConfig"
  type  = "String"
  value = "{\"isEnabled\": false, \"failureMode\": \"latency\", \"rate\": 1, \"minLatency\": 100, \"maxLatency\": 400, \"exceptionMsg\": \"Exception message!\", \"statusCode\": 404, \"diskSpace\": 100}"
}
