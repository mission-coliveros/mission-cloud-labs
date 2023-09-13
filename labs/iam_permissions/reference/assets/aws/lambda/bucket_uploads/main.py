import boto3


def lambda_handler(event, context):
    bucket_name, object_key = event['detail']['bucket']['name'], event['detail']['object']['key']

    print(
        f"A new object was uploaded to {bucket_name} at {event['time']}.\n"
        f"Source IP Address: {event['detail']['source-ip-address']}\n"
        f"Object key:        {object_key}\n"
        f"Object size:       {event['detail']['object']['size']}\n"
    )

    print("Instantiating boto3 client")
    aws_s3_client = boto3.client("s3")

    print("Deleting object")
    aws_s3_client.delete_object(
        Bucket=bucket_name,
        Key=object_key
    )

    print("Delete successful!")
