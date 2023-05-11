import json
import boto3
from boto3.dynamodb.conditions import Key # this is used for the DynamoDB Table Resource

# Use the DynamoDB Table update item method to increment item
def lambda_handler(event, context):
    TABLE_NAME = "VisitCountTotal"  # Used to declare table 
    
    # Creating the DynamoDB Client
    client = boto3.resource("dynamodb")
    table = client.Table(TABLE_NAME)
    
    response = table.get_item(Key={"visitor_id":'visitor_counter'})
    item = response['Item']

    table.update_item(
        Key={"visitor_id":'visitor_counter',},
        UpdateExpression='SET visitor_count = :val1',
        ExpressionAttributeValues={':val1': item['visitor_count'] + 1}
    )
    return{
        'statusCode': 200,
        'headers': {
            'Content-Type': 'application/json',
            'Access-Control-Allow-Origin': '*'
        },
      "body": item['visitor_count'] + 1
    }