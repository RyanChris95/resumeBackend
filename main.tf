terraform{
  # Configure the provider
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "4.52.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "3.4.3"
    }
  }
  required_version = ">= 1.1.0"

  cloud {
    organization = "rdcresume"

    workspaces {
      name = "resume-backend"
    }
  }
}

provider "aws" {
  region = "us-east-2"
}

resource "random_pet" "sg" {}
###  DYNAMODB SETUP  ###

# Create a DynamoDB table
resource "aws_dynamodb_table" "basic-dynamodb-table" {
  name           = "VisitCountTotal"
  billing_mode   = "PAY_PER_REQUEST"
  hash_key       = "visitor_id"

  attribute {
    name = "visitor_id"
    type = "S"
  }

}

# Create an item within the db table
resource "aws_dynamodb_table_item" "VisitCountTotal" {
  table_name = aws_dynamodb_table.basic-dynamodb-table.name
  hash_key = aws_dynamodb_table.basic-dynamodb-table.hash_key

    item = <<ITEM
{
  "visitor_id": {"S": "visitor_counter"},
  "visitor_count": {"N": "0"}
}
ITEM
}

###  LAMBDA FUNCTION SETUP  ###

# Create a lambda role for the lambda function
resource "aws_iam_role" "lambda_role" {
  name = "terraform_aws_lambda_role"
  assume_role_policy = <<EOF
  {
    "Version": "2012-10-17",
    "Statement": [
      {
        "Action": "sts:AssumeRole",
        "Principal": {
          "Service": "lambda.amazonaws.com"
        },
        "Effect": "Allow",
        "Sid": ""
      }
    ]
  }
  EOF
}

# Grants the lambda function access to log to CloudWatch
resource "aws_iam_policy" "BasicLambdaPolicy" {
  name = "BasicLambdaPolicy"
  path = "/"
  description = "Basic function for Lambda to write to CloudWatch"
  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": "logs:CreateLogGroup",
      "Resource": "arn:aws:logs:us-east-2:890467704404:*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "logs:CreateLogStream",
        "logs:PutLogEvents"
      ],
      "Resource": [
        "arn:aws:logs:us-east-2:890467704404:log-group:/aws/lambda/visitorFunc:*"
      ]
    }
  ]
}
  EOF
}

# Grants the lambda function access to read and write to/from the db table
resource "aws_iam_policy" "VisitCountTotalAccess" {
  name = "VisitorCountTotalAccess"
  path = "/"
  description = "Grants access to VisitorCountTable in Dynamodb"
  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "dynamodb:BatchGetItem",
        "dynamodb:GetItem",
        "dynamodb:Query",
        "dynamodb:Scan",
        "dynamodb:BatchWriteItem",
        "dynamodb:PutItem",
        "dynamodb:UpdateItem"
      ],
      "Resource": "arn:aws:dynamodb:us-east-2:890467704404:table/VisitCountTotal"
    }
  ]
}
EOF
}

# Attaches the policies to the lambda role
resource "aws_iam_role_policy_attachment" "attachment" {
  for_each = toset([
    aws_iam_policy.BasicLambdaPolicy.arn,
    aws_iam_policy.VisitCountTotalAccess.arn
  ])

  role       = aws_iam_role.lambda_role.name
  policy_arn = each.value
} 

# turns the python code into a zip file to be uploaded to aws lambda
data "archive_file" "zip_python_code" {
  type = "zip"
  source_dir = "${path.module}/lambda"
  output_path = "${path.module}/lambda/visitorFunc.zip"
}

# Creates the lambda function by uploading the zip file that was created
resource "aws_lambda_function" "visitorFunc" {
  filename = "${path.module}/lambda/visitorFunc.zip"
  function_name = "visitorFunc"
  role = aws_iam_role.lambda_role.arn
  handler = "visitorFunc.lambda_handler"
  runtime = "python3.9"
  depends_on = [aws_iam_role_policy_attachment.attachment]
}
/*
###  API GATEWAY SETUP  ###

# Creates a REST API that calls the lambda function
resource "aws_api_gateway_rest_api" "callVisitorFunc" {
  name        = "callVisitorFunc"
  endpoint_configuration {
    types = ["REGIONAL"]
  }
}

# Adds a resource to the API
resource "aws_api_gateway_resource" "callVisitorFuncResource" {
  rest_api_id = aws_api_gateway_rest_api.callVisitorFunc.id
  parent_id   = aws_api_gateway_rest_api.callVisitorFunc.root_resource_id
  path_part   = "callVisitorFunc"
}

# Creates a GET method within the API
resource "aws_api_gateway_method" "GETMethod" {
  rest_api_id   = aws_api_gateway_rest_api.callVisitorFunc.id
  resource_id   = aws_api_gateway_resource.callVisitorFuncResource.id
  http_method   = "GET"
  authorization = "NONE"
}

# Creates a POST method within the API
resource "aws_api_gateway_method" "POSTMethod" {
  rest_api_id   = aws_api_gateway_rest_api.callVisitorFunc.id
  resource_id   = aws_api_gateway_resource.callVisitorFuncResource.id
  http_method   = "POST"
  authorization = "NONE"
}

# Connects the API with the lambda function for the GET method
resource "aws_api_gateway_integration" "GETintegration" {
  rest_api_id             = aws_api_gateway_rest_api.callVisitorFunc.id
  resource_id             = aws_api_gateway_resource.callVisitorFuncResource.id
  http_method             = aws_api_gateway_method.GETMethod.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.visitorFunc.invoke_arn
}

# Connects the API with the lambda function for the POST method
resource "aws_api_gateway_integration" "POSTintegration" {
  rest_api_id             = aws_api_gateway_rest_api.callVisitorFunc.id
  resource_id             = aws_api_gateway_resource.callVisitorFuncResource.id
  http_method             = aws_api_gateway_method.POSTMethod.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.visitorFunc.invoke_arn
}

# Allows the API to call the lambda function
resource "aws_lambda_permission" "lambda_permission" {
  statement_id  = "AllowcallVisitorFuncInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.visitorFunc.function_name
  principal     = "apigateway.amazonaws.com"

  # The /* part allows invocation from any stage, method and resource path
  # within API Gateway.
  source_arn = "${aws_api_gateway_rest_api.callVisitorFunc.execution_arn}/*"
}

# Deploys the API to be used
resource "aws_api_gateway_deployment" "deployment" {
  rest_api_id = aws_api_gateway_rest_api.callVisitorFunc.id
  triggers = {
    redeployment = sha1(jsonencode(aws_api_gateway_rest_api.callVisitorFunc.body))
  }
  depends_on = [ aws_api_gateway_integration.POSTintegration ]
  lifecycle {
    create_before_destroy = true
  }
}

# Creates a stage to put the deployed API
resource "aws_api_gateway_stage" "prod" {
  deployment_id = aws_api_gateway_deployment.deployment.id
  rest_api_id = aws_api_gateway_rest_api.callVisitorFunc.id
  stage_name = "prod"
}
*/