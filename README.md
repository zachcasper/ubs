# Todolist Demo

This is a step-by-step guide for deploying the Todolist demo application with successively more complexity. It includes:

* **Step 1** – Deploying a single container to Kubernetes using the built-in Radius deployment functionality
* **Step 2** – Adding a Redis cache deployed to Kubernetes using a Terraform configuration
* **Step 3** – Replacing the Redis cache with a PostgreSQL database deployed to Kubernetes using a Terraform configuration (we will also create a resource type since Radius does not ship with a PostgreSQL resource type)
* **Step 4** – Replacing the PostgreSQL recipe so that the database is deployed to Azure
* **Step 5** – As a developer, increasing the storage for the database
* **Step 6** – As a platform engineer, modifying the environment so that the database is deployed in high-availability mode

## Prerequisites

1. The UBS-specific Radius installed on a Kubernetes cluster
1. Radius CLI installed on the workstation (either built from the UBS-specific branch or at least version 0.48)
1. An Azure subscription, resource group, and AKS cluster already created
1. A Git repository for storing the Terraform configurations

## Step 0: Configure Radius
### Clean up previous configurations

Let's start from scratch so it's clear what is happening.

Delete any deployed applications. List all applications then delete each one.

```bash
rad application list
rad application delete <application-name>
```

Ensure there are no containers running on the Kubernetes cluster that Radius deployed. Do this by deleting the `demo-env` namespace and any other namespaces that Radius may have created.

```bash
kubectl get namespaces
kubectl delete namespace demo-env
```

Delete any Radius Resource groups.

```bash
rad group list
rad group delete <group-name>
```

Delete the config file containing workspaces. Remember that a workspace is just a local CLI configuration. It's akin to a Kubernetes context.

```yaml
rm ~/.rad/config.yaml
```

or on Windows

```bash
del %USERPROFILE%\.rad\config.yaml
```

Ensure your current Kubernetes context is set to the correct cluster.

```yaml
kubectl config current-context
```

Update the current context if needed.

```bash
kubectl config use-context <context>
```

### Create a Radius Resource Group and Environment

All resources including Radius environments reside in a resource group just like in Azure (they are completely separate however).

Create a Radius resource group. There is no configuration options for resource groups yet (there will be RBAC rules in the future), so we can just use a simple create command.
```
rad group create demo-todolist
```
Create a corresponding environments. We could use the `rad environment create` imperative command, but since we need more advanced configurations, we will use a declarative approach with a Bicep file. This also saves us from using multiple `rad recipe register` imperative commands. 

This repository includes the `demo-todolist-env.bicep` file. There are four resources defined in this file:

* The demo-todolist environment. 
  * The Kubernetes namespace is `demo`. When we deploy the `todolist` application, Radius will deploy the resources to the `demo-todolist` Kubernetes namespace.
  * The `recipeConfig` contains the authentication for the Git repository, the provider mirror, and the binary location and the certificate authority certificate
  * The recipe for PostgreSQL and Redis
* Three secrets for storing the authentication tokens and certificate

Create the demo-todolist environment.

```bash
rad env create demo-todolist --group demo-todolist
```

Then deploy the Bicep file (in the future this double step will not be required).

```
rad deploy demo-todolist-env.bicep \
  --group demo-todolist \
  --environment demo-todolist \
  --parameters gitToken=<my-pat-token> \
  --parameters registryCACert="$(cat ./ubs_cert.pem)"
```
Create the Radius Workspace. A Workspace is the local CLI configuration. It is a combination of the Kubernetes context, Radius resource group, and Radius environment.
```
rad workspace create kubernetes demo-todolist \
  --context $(kubectl config current-context) \
  --group demo-todolist \
  --environment demo-todolist
```

## Step 1: Deploy a container

Run the Todolist application. The first application definition file deploys only the Todolist container without a database.

```bash
rad run todolist-app-1.bicep --application todolist
```

The `rad run` command sets up port forwarding so that you can access the application and Radius Dashboard without configuring ingress. 

Open http://localhost:3000 in your browser. Click the Todo List in the header. Since there is no database, the application says "No database is configured, items will be stored in memory."

Open http://localhost:7007 in your browser and examine the Radius Dashboard which is built on Backstage. In the future, this dashboard will be a standalone Backstage plug-in and include more developer documentation.

CTRL-C to exit the log stream.

Run the rap app graph command and confirm that Radius has created Kubernetes resources for the PostgreSQL database.

```
rad app graph -a todolist
```

> [!TIP]
> If you prefer for the Radius CLI to not setup port forwarding and log streaming, you can simply run:
> ```bash
> rad deploy todolist-app-1.bicep
> ```
> Once deployed, you can manually port forward using:
> ```bash
> kubectl port-forward $(kubectl get pod -l radapp.io/resource=frontend -n demo-todolist -o name) 3000:3000 -n demo-todolist
> ```

## Step 2: Add a Redis cache

Radius has a pre-defined resource type for [Redis](https://docs.radapp.io/reference/resource-schema/cache/redis/). When we created the environment, a recipe was included which defines how Redis should be deployed. You can see the recipe using the `rad recipe list` command. You should see something similar to:

```bash
$ rad recipe list
RECIPE    TYPE                                 TEMPLATE KIND  TEMPLATE VERSION  TEMPLATE
default   Applications.Datastores/redisCaches  terraform                        git::https://github.com/zachcasper/ubs.git//recipes/kubernetes/redis
default   Radius.Resources/postgreSQL          terraform                        git::https://github.com/zachcasper/ubs.git//recipes/kubernetes/postgresql
```

Run the Todolist application. The second application definition file deploys the same Todolist container but adds a Redis cache resource, and a connection between the container and the cache.

```bash
rad run todolist-app-2.bicep --application todolist
```

Test out the Todo list. It should work and no longer give the "No database is configured" message.

Click the REDIS connection on the main page and examine the environment variables injected into the container.

## Step 3: Swap Redis for PostgreSQL

Unlike Redis, Radius does not have a PostgreSQL resource type. Create the resource type.

```bash
rad resource-type create -f types.yaml
```

You can view the Resource Type properties using the `rad resource-type show` command. The output looks like this:

```bash
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

When creating resource types, a Bicep extension must also be created and added to the bicepconfig.json file. Both of these steps have already been done in this repository.

Run the Todolist application. The third application definition file deploys the same Todolist container but swaps the Redis resource for a PostgreSQL resource and updates the connection.

```bash
rad run todolist-app-3.bicep --application todolist
```

Visiting the Todolist application, you can see that there is a POSTGRESQL connection instead of a REDIS connection.

Manually delete the Redis resource since we deleted it from our application definition file and it is no longer needed.

```bash
rad resource delete Applications.Datastores/redisCaches redis
```

## Step 4: Deploy PostgreSQL to Azure

In order to deploy the PostgreSQL database to Azure, we need to do several steps:

1. Have a subscription and resource group already created
2. Create a service principal and create a credential in Radius (the credential is stored as a Kubernetes secret)
3. Update the environment with the subscription ID and resource group
4. Update the environment with a new recipe that deploys to Azure
5. Deploy the database

### Azure subscription and resource group

If you do not have a subscription and resource group create one. Since you already have an AKS cluster created, the same subscription and resource group can be used (although this is not required).

Set some variables for your Azure subscription and resource group.

```
export AZURE_SUBSCRIPTION_ID=$(az account show | jq  -r '.id')
export AZURE_LOCATION=
export AZURE_RESOURCE_GROUP_NAME=
```

### Azure service principal

In order for Radius to deploy resources to Azure, it must be able to authenticate to Azure. Radius itself must be authenticated to Azure even if you are authenticated on your local workstation. If Radius is not authenticated and you run `rad deploy`, the deployment will fail. Radius can authenticate to Azure using either a [service principal](https://docs.radapp.io/guides/operations/providers/azure-provider/howto-azure-provider-sp/) or if [workload identity](https://docs.radapp.io/guides/operations/providers/azure-provider/howto-azure-provider-wi/) is set up. This sample assumes a service principal.

Create a service principal if you do not already have one and set environment variables.
```
az ad sp create-for-rbac --role Owner --scope /subscriptions/$AZURE_SUBSCRIPTION_ID > azure-credentials.json
export AZURE_CLIENT_ID=$(jq -r .'appId' azure-credentials.json)
export AZURE_CLIENT_SECRET=$(jq -r .'password' azure-credentials.json)
export AZURE_TENANT_ID=$(jq -r .'tenant' azure-credentials.json)
```
Add the service principal as a credential in Radius. Credentials today are stored at the Radius top level. In the future, we plan to move credentials to the environment level to enable multiple subscriptions.
```
rad credential register azure sp --client-id $AZURE_CLIENT_ID  --client-secret $AZURE_CLIENT_SECRET --tenant-id $AZURE_TENANT_ID
```
### Point the environment to the Azure resource group

Update the environment with the Azure details.

```
rad environment update demo-todolist \
  --group demo-todolist \
  --azure-subscription-id $AZURE_SUBSCRIPTION_ID \
  --azure-resource-group $AZURE_RESOURCE_GROUP_NAME
```
**Note:** We are using the imperitive CLI commands since the environment already exists. Alternatively, you could have updated the `demo-todolist-env.bicep` file with the subscription and resource group then redeployed it. The `demo-todolist-env.bicep` file has an example commented out for your reference.

You can confirm the environment was updated using the `rad environment show demo-todolist -o json` command. The output should be similar to:

```bash
$ rad env show demo-todolist -o json                
{
  "id": "/planes/radius/local/resourcegroups/demo-todolist/providers/Applications.Core/environments/demo-todolist",
  "location": "global",
  "name": "demo-todolist",
  "properties": {
    "compute": {
      "kind": "kubernetes",
      "namespace": "demo"
    },
    "providers": {
      "azure": {
        "scope": "/subscriptions/c95e0456-ea5b-4a22-a0cd-e3767f24725b/resourceGroups/ubs"
...
```

Optionally, delete the file containing the credentials.

```
rm azure-credentials.json
```

### Update the PostgreSQL recipe

The `rad recipe register` command updates the environment definition.

```bash
rad recipe register default \
  --resource-type Radius.Resources/postgreSQL \
  --template-kind terraform \
  --template-path git::https://github.com/zachcasper/ubs.git//recipes/azure/postgresql \
  --parameters resource_group_name=$AZURE_RESOURCE_GROUP_NAME \
  --parameters location=$AZURE_LOCATION
```

Some explaination of this command is warranted. 

* `rad recipe register` – This is creating a pointer to a Terraform configuration or a Bicep template which will be called when a resource is created in Radius.
* `rad recipe register default` – Each recipe has a name but you should use default. This is legacy functionality which will be retired. With older resource types which are built into Radius such as Redis and MongoDB, developers could specify a named recipe to be used to deploy the resource. The newer resource types such as the PostgreSQL resource type we are defining here will not allow developers to specify a recipe name. 
* `--template-path git::https://github.com/zachcasper/ubs.git//recipes/kubernetes/postgresql` – This is the path to the Terraform configuration. Radius uses the generic Git module source as [documented here](https://developer.hashicorp.com/terraform/language/modules/sources#generic-git-repository). In the example here, the Git repository on GitHub is UBS. The `//` indicates a sub-module or a sub-directory and postgresql is the directory containing the main.tf file.

* Notice that there are parameters on this recipe which were not on the Kubernetes recipes. There is a bug where Radius is not setting the resource group or location on the context variable which gets passed to the recipe. The parameters arguement forces a variable to be set in the Terraform configuration. You'll see this variable referenced in the `azure/postgresql/main.tf` on line 20 and 25 (``var.resource_group_name` and `var.location`). In the future these variables would be `var.context.azure.resourceGroup` and the parameter will not be required.

### Deploy the database

There are no changes to the application definition so we will use the same file from the previous step. This will now deploy the database to Azure.

```bash
rad run todolist-app-3.bicep 
```

Deploying an Azure Database for PostgreSQL Flexible Server takes approximately 10 minutes.

## Step 5: Modify the PostgreSQL resource

The PostgreSQL resource type has a `storage_gb` property. Azure Database for PostgresSQL Flexible Server defaults to provisioning 32GiB of storage. With the `storage_gb` property, the developer can increase the storage as needed.

Modify the `todolist-app-3.bicep`by changing line 41 from `storage_gb: 32` to `storage_gb: 64`. The full resource should look like this:

```yaml
resource postgresql 'Radius.Resources/postgreSQL@2023-10-01-preview' = {
  name: 'postgrssql'
  properties: {
    application: todolist.id
    environment: environment
    size: 'S' 
    storage_gb: 64
  }
}
```

Redeploy the application.

```bash
rad deploy todolist-app-3.bicep 
```

Using the Azure portal, confirm the storage has been increased to 64 GiB.

## Step 6: Set the database in high-availability mode

Update the recipe with a `ha=true` parameter. This parameter is passed directly to the Terraform configuration. You can see on line 67 that if `ha` is true, it configures the database in high-availability mode.

```bash
rad recipe register default \
  --resource-type Radius.Resources/postgreSQL \
  --template-kind terraform \
  --template-path git::https://github.com/zachcasper/ubs.git//recipes/azure/postgresql \
  --parameters resource_group_name=$AZURE_RESOURCE_GROUP_NAME \
  --parameters location=$AZURE_LOCATION \
  --parameters ha=true
```
Deploy the application again.

```bash
rad deploy todolist-app-3.bicep 
```

Using the Azure portal, confirm that the database was created in high-availability mode.

## Clean up
Delete both applications.
```
rad app delete todolist
```
Verify the pods are terminated on the Kubernetes cluster.
```
kubectl get pods -A
```
Delete the namespaces if the pods still exist. This is not expected but just to make sure. When you delete the application the namespaces are retained but the pods should be destroyed. 
```
kubectl delete namespace demo-todolist
```
Verify the Azure PostgreSQL database has been deleted via the Azure portal. This is not expected just to make sure.

Optionally, delete the Radius environments, Radius resource groups, and associated workspaces.
```
rad environment delete demo-todolist
rad group delete demo-todolist
```
Optionally delete the Azure resource groups (if it doesn't contain the AKS cluster).
```
az group delete --location $AZURE_LOCATION --resource-group $AZURE_RESOURCE_GROUP_NAME
```

## To Do

Fix recipes and container images