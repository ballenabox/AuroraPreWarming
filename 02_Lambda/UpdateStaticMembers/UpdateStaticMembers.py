import json
import logging

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event, context):
    """
    Lambda function to update StaticMembers array by adding a new DbInstanceIdentifier
    
    Parameters:
    - event: Contains StaticMembers array and DbInstanceIdentifier to add
    - context: Lambda context
    
    Returns:
    - Dictionary containing the updated StaticMembers array
    """
    logger.info(f"Received event: {json.dumps(event)}")
    
    # Extract input values
    static_members = event.get('StaticMembers', [])
    db_instance_id = event.get('DbInstanceIdentifier')
    
    # Add the new instance ID to the array if it's not already there
    if db_instance_id and db_instance_id not in static_members:
        static_members.append(db_instance_id)
    
    logger.info(f"Updated StaticMembers: {static_members}")
    
    # Return the updated array
    return {
        "updatedStaticMembers": static_members
    }