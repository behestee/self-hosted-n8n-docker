import boto3
import logging
import json

logger = logging.getLogger()
logger.setLevel(logging.INFO)

ec2 = boto3.client("ec2")


def lambda_handler(event, context):
    """
    Expected event payload from EventBridge Scheduler:
    {
        "action": "start" | "stop",
        "schedule_name": "business-hours"   # must match the EC2 tag value
    }

    EC2 instances must have a tag:
        Key:   Schedule
        Value: <schedule_name>
    """
    action = event.get("action")
    schedule_name = event.get("schedule_name")

    if action not in ("start", "stop"):
        raise ValueError(f"Invalid action '{action}'. Must be 'start' or 'stop'.")
    if not schedule_name:
        raise ValueError("'schedule_name' is required in the event payload.")

    logger.info(f"Action: {action} | Schedule: {schedule_name}")

    # Find all EC2 instances tagged with this schedule
    instances = get_instances_by_schedule(schedule_name)

    if not instances:
        logger.info(f"No instances found with Schedule={schedule_name}")
        return {"statusCode": 200, "body": "No matching instances."}

    instance_ids = [i["InstanceId"] for i in instances]
    logger.info(f"Found {len(instance_ids)} instance(s): {instance_ids}")

    if action == "start":
        result = start_instances(instance_ids)
    else:
        result = stop_instances(instance_ids)

    logger.info(f"Result: {json.dumps(result)}")
    return {"statusCode": 200, "body": result}


def get_instances_by_schedule(schedule_name: str) -> list:
    """Return all instances (any state) tagged with the given schedule name."""
    paginator = ec2.get_paginator("describe_instances")
    pages = paginator.paginate(
        Filters=[
            {"Name": "tag:Schedule", "Values": [schedule_name]},
        ]
    )
    instances = []
    for page in pages:
        for reservation in page["Reservations"]:
            instances.extend(reservation["Instances"])
    return instances


def start_instances(instance_ids: list) -> dict:
    """Start instances that are currently stopped."""
    stopped = [
        i for i in get_instances_detail(instance_ids) if i["State"]["Name"] == "stopped"
    ]
    if not stopped:
        logger.info("No instances in 'stopped' state to start.")
        return {"started": [], "skipped": instance_ids}

    ids_to_start = [i["InstanceId"] for i in stopped]
    response = ec2.start_instances(InstanceIds=ids_to_start)
    started = [s["InstanceId"] for s in response["StartingInstances"]]
    skipped = list(set(instance_ids) - set(ids_to_start))
    logger.info(f"Started: {started} | Skipped (not stopped): {skipped}")
    return {"started": started, "skipped": skipped}


def stop_instances(instance_ids: list) -> dict:
    """Stop instances that are currently running."""
    running = [
        i for i in get_instances_detail(instance_ids) if i["State"]["Name"] == "running"
    ]
    if not running:
        logger.info("No instances in 'running' state to stop.")
        return {"stopped": [], "skipped": instance_ids}

    ids_to_stop = [i["InstanceId"] for i in running]
    response = ec2.stop_instances(InstanceIds=ids_to_stop)
    stopped = [s["InstanceId"] for s in response["StoppingInstances"]]
    skipped = list(set(instance_ids) - set(ids_to_stop))
    logger.info(f"Stopped: {stopped} | Skipped (not running): {skipped}")
    return {"stopped": stopped, "skipped": skipped}


def get_instances_detail(instance_ids: list) -> list:
    """Fetch current state for a list of instance IDs."""
    response = ec2.describe_instances(InstanceIds=instance_ids)
    instances = []
    for reservation in response["Reservations"]:
        instances.extend(reservation["Instances"])
    return instances
