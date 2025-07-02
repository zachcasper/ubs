# PostgreSQL Sample using Azure Database for PostgreSQL

This tutorial is based on the staged [Create a Resource Type in Radius](https://docs.radapp.io/tutorials/create-resource-type/) tutorial with some improvements:

* PostgreSQL is deployed to Azure instead of Kubernetes. The Recipe uses Azure Database for PostgreSQL Flexible Server
* An additional property is exposed to the developer to specify the storage in GiB
* A Recipe parameter is used to determine if the database should be configured in high-availability mode or not

## Prerequisites

1. Radius CLI at least version 0.48 installed on the workstation
1. An Azure subscription, resource group, and AKS cluster already created
1. Node.js installed on the workstation (this is [temporary](https://github.com/radius-project/radius/issues/9230))
1. A Git repository for storing the Terraform configurations; this tutorial will assumes anonymous access to the Git repository, if that is not the case see [this documentation](https://docs.radapp.io/guides/recipes/terraform/howto-private-registry/)

### Air-Gapped Environments
This tutorial requires access to several resources on the internet. While it is possible to perform these actions in an air-gapped environment, that requires additional configuration out of scope for this sample.

## Step 1: Install Radius on AKS
This tutorial will set up three environments: dev, test, and prod. The dev environment will use recipes which deploy all resources to the Kubernetes cluster. The test environment will deploy containers to the Kubernetes cluster, but the PostgreSQL database using Azure Database for PostgreSQL in non-HA mode. The prod environment will also deploy containers to Kubernetes but the Azure Database for PostgreSQL is configured in high-availability mode.

### Prepare Azure
Set some variables for your Azure subscription and resource group.
```
export AZURE_SUBSCRIPTION_ID=`az account show | jq  -r '.id'`
export AZURE_LOCATION=
export AKS_CLUSTER_NAME=
export AKS_CLUSTER_RESOURCE_GROUP_NAME=
export DEV_RESOURCE_GROUP_NAME=
export TEST_RESOURCE_GROUP_NAME=
export PROD_RESOURCE_GROUP_NAME=
```
Get the kubecontext for your AKS cluster if it's not already set.
```
az aks get-credentials --resource-group $AKS_CLUSTER_RESOURCE_GROUP_NAME --name $AKS_CLUSTER_NAME
```
We need three Azure resource groups for each of our environments.
```
az group create --location $AZURE_LOCATION --resource-group $DEV_RESOURCE_GROUP_NAME
az group create --location $AZURE_LOCATION --resource-group $TEST_RESOURCE_GROUP_NAME
az group create --location $AZURE_LOCATION --resource-group $PROD_RESOURCE_GROUP_NAME
```

### Install Radius.
Install Radius.
```
rad install kubernetes
```

### Create the Radius Resource Groups and Environments
All resources including Radius environments reside in a resource group just like in Azure. Since we will be deploying the same application to three different environments, we need three separate resource groups.

Create three resource groups.
```
rad group create dev
rad group create test
rad group create prod
```
Create the environments.
```
rad environment create dev --group dev
rad environment create test --group test
rad environment create prod --group prod
```
Create the Radius Workspace. A Workspace is the local CLI configuration. It is a combination of the Kubernetes context, Radius resource group, and Radius environment.
```
rad workspace create kubernetes dev --context $RADIUS_NAME --group dev --environment dev --force
rad workspace create kubernetes test --context $RADIUS_NAME --group test --environment test --force
rad workspace create kubernetes prod --context $RADIUS_NAME --group prod --environment prod --force
```

### Setup Azure authentication
In order for Radius to deploy resources to Azure, it must be able to authenticate. Radius itself must be authenticated to Azure even if you are authenticated on your local workstation. If Radius is not authenticated and you run `rad deploy`, the deployment will fail. Radius can authenticate to Azure using either a [service principal](https://docs.radapp.io/guides/operations/providers/azure-provider/howto-azure-provider-sp/) or if [workload identity](https://docs.radapp.io/guides/operations/providers/azure-provider/howto-azure-provider-wi/) is set up. This tutorial assumes a service principal.

Create a service principal if you do not already have one and set environment variables.
```
az ad sp create-for-rbac --role Owner --scope /subscriptions/$AZURE_SUBSCRIPTION_ID > azure-credentials.json
export AZURE_CLIENT_ID=`jq -r .'appId' azure-credentials.json`
export AZURE_CLIENT_SECRET=`jq -r .'password' azure-credentials.json`
export AZURE_TENANT_ID=`jq -r .'tenant' azure-credentials.json`
```
Add the service principal as a credential in Radius. Credentials today are stored at the Radius top level. In the future, we plan to move credentials to the environment level to enable multiple subscriptions.
```
rad credential register azure sp --client-id $AZURE_CLIENT_ID  --client-secret $AZURE_CLIENT_SECRET --tenant-id $AZURE_TENANT_ID
```
Update the dev, test, and prod environments with the Azure details.
```
rad environment update dev \
  --group dev \
  --azure-subscription-id $AZURE_SUBSCRIPTION_ID \
  --azure-resource-group $DEV_RESOURCE_GROUP_NAME
rad environment update test \
  --group test \
  --azure-subscription-id $AZURE_SUBSCRIPTION_ID \
  --azure-resource-group $TEST_RESOURCE_GROUP_NAME
rad environment update prod \
  --group prod \
  --azure-subscription-id $AZURE_SUBSCRIPTION_ID \
  --azure-resource-group $PROD_RESOURCE_GROUP_NAME
```
**Note:** This sample walks you through using imperitive CLI commands to teach you. In a real-life scenario, all of this configuration would be in a single configuration file which you would deploy all at once.


Delete the file containing the credentials.
```
rm azure-credentials.json
```

## Step 2: Define the PostgreSQL resource type API
Radius Resource Types are the contracts between developers and the platform. Resource Types are defined using an OpenAPI schema in a YAML file. 
```
rad resource-type create -f types.yaml
```
You can view the Resource Type properties using the `rad resource-type show` command. The output looks like this:
```
$ rad resource-type show Radius.Resources/postgreSQL
TYPE                         NAMESPACE
Radius.Resources/postgreSQL  Radius.Resources

DESCRIPTION:
A PostgreSQL database. The size property is required. The storage_gb property is optional but defaults to 32.

API VERSION: 2023-10-01-preview

TOP-LEVEL PROPERTIES:

NAME         TYPE      REQUIRED  READ-ONLY  DESCRIPTION
application  string    false     false      The ID of the Radius Application
database     string    false     true       The name of the database
environment  string    true      false      The ID of the Radius Environment, typically set by the Radius CLI
host         string    false     true       The host name of the database
password     string    false     true       The password for the database
port         string    false     true       The port number of the database
size         string    true      false      The size of the PostgreSQL database, accepts S, M, L, XL
username     string    false     true       The username for the database
```
The non-read-only properties are set by the developer. The read-only properties are outputs from the deployments and can be used in other resources.

## Step 3: Define the PostgreSQL implementation

Resources are deployed via Recipes. Recipes are either Terraform configurations or Bicep templates. In this sample, Terraform configurations stored in a Git repository are used.

The recipes directory of this repository containers two Terraform recipes for deploying a PostgreSQL database, one for Kubernetes and one for Azure. The Kubernetes recipe will be used for the dev environment while the Azure recipe will be used for the test and prod environment.

### Dev environment

Register the Kubernetes recipe in the dev environment.
```
rad recipe register default \
  --workspace dev \
  --resource-type Radius.Resources/postgreSQL \
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
  --workspace test \
  --resource-type Radius.Resources/postgreSQL \
  --template-kind terraform \
  --template-path git::https://github.com/zachcasper/ubs.git//recipes/azure/postgresql \
  --parameters resource_group_name=$TEST_RESOURCE_GROUP_NAME \
  --parameters location=$AZURE_LOCATION
```
Notice that there are parameters on this recipe which were not on the dev environments. There is a bug where Radius is not setting the resource group or location on the context variable which gets past to the recipe. The parameters arguement forces a variable to be set in the Terraform configuration. You'll see this variable referenced in the azure/postgresql/main.tf on line 20 and 25 (var.resource_group_name and var.location). In the future these variables would be var.context.azure.resourceGroup and the parameter will not be required.

### Prod environment

Register the Azure recipe in the prod environment.
```
rad recipe register default \
  --workspace prod \
  --resource-type Radius.Resources/postgreSQL \
  --template-kind terraform \
  --template-path git::https://github.com/zachcasper/ubs.git//recipes/azure/postgresql \
  --parameters resource_group_name=$PROD_RESOURCE_GROUP_NAME \
  --parameters location=$AZURE_LOCATION \
  --parameters ha=true
```
For the prod environment, we added a `ha` parameter for the Recipe. This parameter is passed directly to the Terraform configuration. You can see on line 67 that if `ha` is true, it configures the database in high-availability mode.

### Create the Bicep extension

Since we created a new resource type, we must tell Bicep how to handle it. This is performed by creating a Bicep extension. Bicep extensions can be stored in either Azure Container Registry or on the file system. This example will use the file system. The documentation for using a private module registry is [here](https://learn.microsoft.com/en-us/azure/azure-resource-manager/bicep/quickstart-private-module-registry?tabs=azure-cli).

Create the Bicep extension.
```
rad bicep publish-extension -f types.yaml --target radiusResources.tgz
```
Update the bicepconfig.json file to include the extension. The bicepconfig.json included in this example has already been updated. Consult the documentation on having multiple bicepconfig.json files if you are interested. Note that when you when your bicepconfig.json file is stored in a different directory than your .tgz extension file, you must reference the extension file using the full path name, not a relative path.

## Step 4: Run the todolist application in dev
Make sure you are using the dev environment.
```
rad workspace switch dev
```
Deploy the todolist application.
```
rad run todolist.bicep -a todolist
```
The `rad run` command will automatically setup port forwarding to our application.

Open http://localhost:3000 in your browser. Click the POSTGRESQL environment variable and examine the environment variables injected into the container.

Open http://localhost:7007 in your browser and examine the Radius Dashboard which is built on Backstage. In the future, this dashboard will be a standalone Backstage plug-in and include more developer documentation.

CTRL-C to exit the log stream.

### Examine the resources deployed
Run the rap app graph command and confirm that Radius has created Kubernetes resources for the PostgreSQL database.
```
rad app graph -a todolist
```

## Step 5: Deploy the todolist application to test
Switch to the test enviornment
```
rad workspace switch test
```
Deploy the todolist application.
```
rad deploy todolist.bicep
```

### Examine the resources deployed
Use the same `rap app graph -a todolist` command and confirm that Radius has created the PostgreSQL database on Azure.


## Step 6: Deploy the todolist application to prod
Switch to the prod enviornment
```
rad workspace switch prod
```
Deploy the todolist application.
```
rad deploy todolist.bicep
```

### Examine the resources deployed
Use the same `rad app graph -a todolist` command and confirm that Radius has created the PostgreSQL database on Azure.

Using the Azure portal, confirm that the database was created in high-availability mode.

## Clean up
Delete both applications.
```
rad app delete --workspace dev
rad app delete --workspace test
rad app delete --workspace prod
```
Verify the pods are terminated on the Kubernetes cluster.
```
kubectl get pods -A
```
Delete the namespaces if the pods still exist. This is not expected but just to make sure. When you delete the application the namespaces are retained but the pods should be destroyed. 
```
kubectl delete namespace dev-todolist
kubectl delete namespace test-todolist
kubectl delete namespace prod-todolist
```
Verify the Azure PostgreSQL database has been deleted via the Azure portal. This is not expected just to make sure.

Optionally, delete the Radius environments, Radius resource groups, and associated workspaces.
```
rad environment delete dev
rad group delete dev
rad workspace delete dev
rad environment delete test
rad group delete test
rad workspace delete test
rad environment delete prod
rad group delete prod
rad workspace delete prod
```
Optionally, uninstall Radius
```
rad uninstall kubernetes
```
Finally, optionally delete the Azure resource groups.
```
az group delete --location $AZURE_LOCATION --resource-group $DEV_RESOURCE_GROUP_NAME
az group delete --location $AZURE_LOCATION --resource-group $TEST_RESOURCE_GROUP_NAME
az group delete --location $AZURE_LOCATION --resource-group $PROD_RESOURCE_GROUP_NAME
```