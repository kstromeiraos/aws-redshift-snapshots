#!/bin/bash 

# AWS Redshift Restore Snapshot
# Script to restore a snapshot from an AWS Redshift cluster into another one.
# Copyright (C) 2018 Jose López <dev@kstromeiraos.com>

usage() { 
    echo "usage: ./redshift_restore_snapshot <cluster_identifier_to_restore> <cluster_identifier_to_snapshot>"
    echo "  -h      display help"
} 

main(){
    # Get current data from the cluster 
    AVAILABILITY_ZONE=`aws redshift describe-clusters --cluster-identifier "$1" | jq '.Clusters[].AvailabilityZone' | tr -d '"'`
    PUBLIC_IP=`aws redshift describe-clusters --cluster-identifier "$1" | jq '.Clusters[].ElasticIpStatus.ElasticIp' | tr -d '"'`
    VPC_SECURITY_GROUPS=`aws redshift describe-clusters --cluster-identifier "$1" | jq '.Clusters[].VpcSecurityGroups[].VpcSecurityGroupId' | tr -d '"'`
    PARAMETER_GROUP_NAME=`aws redshift describe-clusters --cluster-identifier "$1" | jq '.Clusters[].ClusterParameterGroups[].ParameterGroupName' | tr -d '"'`
    SUBNET_GROUP_NAME=`aws redshift describe-clusters --cluster-identifier "$1" | jq '.Clusters[].ClusterSubnetGroupName' | tr -d '"'`

    # Delete cluster to restore snapshot into
    read -r -p "Cluster $1 needs to be deleted to be able to restore from the specified snapshot, a final snapshot will be created, are you sure to delete it? [y/N] " response
    if [[ "$response" =~ ^([yY][eE][sS]|[yY])+$ ]]
    then
        DATE=`/bin/date +%Y%m%d%H%M%S`
        aws redshift delete-cluster --cluster-identifier $1 --final-cluster-snapshot-identifier "$1-${DATE}"
        echo -e "\nDeleting $1 cluster"
    else
        exit 0
    fi

    # Wait for the cluster to be deleted
    until ! aws redshift describe-clusters --cluster-identifier $1 > /dev/null 2>&1;
    do
        printf "."
        sleep 1
    done

    # Look for the last snapshot ID of the origin cluster
    LAST_SNAPSHOT_DATE=`aws redshift describe-cluster-snapshots --cluster-identifier $2 | jq '.Snapshots[] .SnapshotCreateTime' | head -1`
    LAST_SNAPSHOT=`aws redshift describe-cluster-snapshots --cluster-identifier $2 | jq '.Snapshots[]  | select(.SnapshotCreateTime == '$LAST_SNAPSHOT_DATE') |.SnapshotIdentifier' | tr -d '"'`

    # Restore cluster from snapshot
    aws redshift restore-from-cluster-snapshot --cluster-identifier $1 --snapshot-identifier "${LAST_SNAPSHOT}" --cluster-subnet-group-name ${SUBNET_GROUP_NAME} --availability-zone "${AVAILABILITY_ZONE}" --elastic-ip ${PUBLIC_IP} --vpc-security-group-ids "${VPC_SECURITY_GROUPS}" --cluster-parameter-group-name "${PARAMETER_GROUP_NAME}" --publicly-accessible
    echo -e "\nRestoring $1 cluster from snapshot $LAST_SNAPSHOT..."

    # Wait for the cluster to be restored
    until [[ `aws redshift describe-clusters --cluster-identifier $1 | jq '.Clusters[].RestoreStatus.Status'` != "completed" ]];
    do
        printf "."
        sleep 1
    done

    echo -e "\nCluster $1 sucessfully restored!"
    exit 0
}

# SCRIPT
		
# If less than two arguments supplied, display usage 
if [  $# -le 1 ] 
then 
    usage
    exit 1
fi 
 
# Check whether user had supplied -h or --help. If yes display usage 
if [[ ( $# == "--help") ||  $# == "-h" ]] 
then 
    usage
    exit 0
fi

main $1 $2