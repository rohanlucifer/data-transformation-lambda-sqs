# output of lambda arn
output "arn" {
  value = aws_lambda_function.data_transformation_lambda.arn
}
