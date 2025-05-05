# PostgreSQL Example using Azure Database for PostgreSQL

This tutorial is based on the staged [Create a Resource Type in Radius](https://red-sea-07f97dc1e-1409.westus2.3.azurestaticapps.net/tutorials/tutorial-resource-type/) tutorial. The only difference between that tutorial and this one is the inclusion of using an Azure Database for PostgreSQL resource and the ability to specify the database name.

## Prerequisites

1. Radius CLI at least version 0.46 installed on the workstation
1. Node.js installed on the workstation
1. An AKS cluster in an Azure resource group
1. A Git repository for storing the Terraform configurations; this tutorial will assumes anonymous access to the Git repository, if that is not the case see [this documentation](https://red-sea-07f97dc1e-1409.westus2.3.azurestaticapps.net/guides/recipes/terraform/howto-private-registry/)

## Install Radius on AKS
This tutorial will set up two environments: dev and test. The dev environment will use recipes which deploy all resources to the Kubernetes cluster. The test environment will deploy containers to Kubernetes and other resources, such as databases, to Azure.

Set some variables for your Azure subscription and resource group.
```
export AZURE_SUBSCRIPTION_ID=`az account show | jq  -r '.id'`
export AZURE_RESOURCE_GROUP_NAME=myresourcegroup
export AKS_CLUSTER_NAME=mycluster
```
Get the kubecontext for your AKS cluster if it's not already set.
```
az aks get-credentials --resource-group $AZURE_RESOURCE_GROUP_NAME --name $AKS_CLUSTER_NAME
```
### Install Radius.
Set the environment variables.
```
export RADIUS_CHART=
export REGISTRY_HOST=
export RADIUS_VERSION=
```
Install Radius.
```
rad install kubernetes \
  --chart ${RADIUS_CHART} \
  --set rp.image=${REGISTRY_HOST}/radius-project/applications-rp,rp.tag=${RADIUS_VERSION} \
  --set dynamicrp.image=${REGISTRY_HOST}/radius-project/dynamic-rp,dynamicrp.tag=${RADIUS_VERSION} \
  --set controller.image=${REGISTRY_HOST}/radius-project/controller,controller.tag=${RADIUS_VERSION} \
  --set ucp.image=${REGISTRY_HOST}/radius-project/ucpd,ucp.tag=${RADIUS_VERSION} \
  --set bicep.image=${REGISTRY_HOST}/radius-project/bicep,bicep.tag=${RADIUS_VERSION} \
  --set de.image=${REGISTRY_HOST}/radius-project/deployment-engine,de.tag=${RADIUS_VERSION} \
  --set dashboard.image=${REGISTRY_HOST}/radius-project/dashboard,dashboard.tag=${RADIUS_VERSION}
```
Create a resource group in Radius. All resources including Radius environments reside in a resource group just like in Azure. Today, there resource groups do not provide a lot of functionality, but in the future, Radius will have RBAC rules tied to resource groups. You can just use  `default` for now or call the group whatever you like.
```
rad group create default
```
### Create the dev environment
Create a dev environment in the default resource group.
```
rad environment create dev --group default
```
Set the Radius CLI configuration file. Radius uses the term workspace to refer to a specific combination of Radius installation, environment, and group.
```
rad workspace create kubernetes dev --context $AKS_CLUSTER_NAME --environment dev --group default
```
### Create the test environment
Create a test environment in the default resource group.
```
rad environment create test --group default
```
Set the Radius CLI configuration file. Radius uses the term workspace to refer to a specific combination of Radius installation, environment, and group.
```
rad workspace create kubernetes test --context $AKS_CLUSTER_NAME --environment test --group default
```
### Setup Azure authentication
In order for Radius to deploy resources to Azure, it must be able to authenticate. Radius itself must be authenticated to Azure even if you are authenticated on your local workstation. If Radius is not authenticated and you run `rad deploy`, the deployment will fail. Radius can authenticate to Azure using either a [service principal](https://docs.radapp.io/guides/operations/providers/azure-provider/howto-azure-provider-sp/) or if [workload identity](https://docs.radapp.io/guides/operations/providers/azure-provider/howto-azure-provider-wi/) is set up. This tutorial assumes a service principal.

Create a service principal if you do not already have one and set environment variables.
```
az ad sp create-for-rbac --role Owner --scope /subscriptions/$AZURE_SUBSCRIPTION_ID/resourceGroups/$INSTANCE_NAME > /tmp/sp.json
export AZURE_CLIENT_ID=`jq -r .'appId' /tmp/sp.json`
export AZURE_CLIENT_SECRET=`jq -r .'password' /tmp/sp.json`
export AZURE_TENANT_ID=`jq -r .'tenant' /tmp/sp.json`
rm /tmp/sp.json
```
Update the Radius environment.
```
rad environment update $AKS_CLUSTER_NAME --azure-subscription-id $AZURE_SUBSCRIPTION_ID --azure-resource-group $AZURE_RESOURCE_GROUP_NAME
rad credential register azure sp --client-id $AZURE_CLIENT_ID  --client-secret $AZURE_CLIENT_SECRET --tenant-id $AZURE_TENANT_ID
```

## Create PostgreSQL resource type

```
rad resource-type create postgreSQL -f types.yaml
```

## Register the PostgreSQL recipe

Commit the recipes directory into a Git repository. This directory has two Terraform recipes for deploying a PostgreSQL database, one for Kubernetes and one for Azure. The Kubernetes recipe will be used for the dev environment while the Azure recipe will be used for the test environment.

### Dev environment

Register the Kubernetes recipe in the dev environment.
```
rad recipe register default \
  --environment dev \
  --resource-type MyCompany.Radius/postgreSQL \
  --template-kind terraform \
  --template-path git::https://github.com/zachcasper/ubs.git//recipes/kubernetes/postgresql
```
Some explaination of this command is warranted. 

* `rad recipe register` – This is creating a pointer to a Terraform configuration or a Bicep template which will be called when a resource is created in Radius.
* `rad recipe register default` – Each recipe has a name but you should use default. This is legacy functionality which will be retired. With older resource types which are built into Radius such as Redis and MongoDB, developers could specify a named recipe to be used to deploy the resource. The newer resource types such as the PostgreSQL resource type we are defining here will not allow developers to specify a recipe name. 
* `--template-path git::https://github.com/zachcasper/ubs.git//recipes/kubernetes/postgresql` – This is the path to the Terraform configuration. Radius uses the generic Git module source as [documented here](https://developer.hashicorp.com/terraform/language/modules/sources#generic-git-repository). In the example here, the Git repository on GitHub is UBS. The `//` indicates a sub-module or a sub-directory and postgresql is the directory containing the main.tf file.

### Test environment

Register the Azure recipe in the test environment.
```
rad recipe register default \
  --environment test \
  --resource-type MyCompany.Radius/postgreSQL \
  --template-kind terraform \
  --template-path git::https://github.com/zachcasper/ubs.git//recipes/azure/postgresql
```

## Create the Bicep extension

Since we created a new resource type, we must tell Bicep how to handle it. This is performed by creating a Bicep extension. Bicep extensions can be stored in either Azure Container Registry or on the file system. This example will use the file system. The documentation for using a private module registry is [here](https://learn.microsoft.com/en-us/azure/azure-resource-manager/bicep/quickstart-private-module-registry?tabs=azure-cli).

Create the extension for MyCompany.
```
rad bicep publish-extension -f types.yaml --target mycompany.tgz
```
Update the bicepconfig.json file to include the extension. The bicepconfig.json included in this example has already been updated. Consult the documentation on having multiple bicepconfig.json files if you are interested. Note that when you when your bicepconfig.json file is stored in a different directory than your .tgz extension file, you must reference the extension file using the full path name, not a relative path.

## Deploy the todolist application to dev
Make sure you are using the dev environment.
```
rad workspace switch dev
```
Deploy the todolist application.
```
rad deploy todolist.bicep
```
### Port forward and open the application
Use kubectl to port forward the frontend pod. Typically in a shared environment, the container would have a gateway resource which would setup an ingress controller using Contour. Since we installed Radius without Contour, the gateway resource will not work. 
```
kubectl port-forward `kubectl get pods -n dev-todolist | grep frontend | awk '{print $1}'` 3000:3000 -n dev-todolist
```
Open http://localhost:3000 in your browser. Click the POSTGRESQL environment variable and examine the environment variables injected into the container.

We could have also used `rad run todolist.bicep -a todolist` which would have setup port forwarding automatically.

### Examine the resources deployed
Run the rap app graph command and confirm that Radius has created Kubernetes resources for the PostgreSQL database.
```
rad app graph -a todolist
```

## Deploy the todolist application to test
Switch to the test enviornment
```
rad workspace switch test
```
Deploy the todolist application.
```
rad deploy todolist.bicep
```
### Port forward and open the application
Use the same kubectl port-forward command as before, but change the namespace from dev-todolist to test-todolist. 

### Examine the resources deployed
Use the same `rap app graph -a todolist` command and confirm that Radius has created the PostgreSQL database on Azure.
