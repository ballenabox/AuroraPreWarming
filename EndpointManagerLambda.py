import boto3
import json
import logging

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event, context):
    
    DbClusterIdentifier = event['DbClusterIdentifier']
    DbClusterEndpointIdentifier = event['DbClusterEndpointIdentifier']

    client=boto3.client('rds')
    response = client.describe_db_clusters(
        DBClusterIdentifier=DbClusterIdentifier,
        DbClusterEndpointIdentifier=DbClusterEndpointIdentifier
    )

    endpoint_info = response.get('DBClusterEndpoints').get('StaticMembers')
    return endpoint_info