extension radius
extension radiusResources

param environment string

resource todolist 'Applications.Core/applications@2023-10-01-preview' = {
  name: 'todolist'
  properties: {
    environment: environment
  }
}

resource frontend 'Applications.Core/containers@2023-10-01-preview' = {
  name: 'frontend'
  properties: {
    application: todolist.id
    environment: environment
    
    container: {
      image: 'ghcr.io/radius-project/samples/demo:latest'
      ports: {
        http: {
          containerPort: 3000
        }
      }
    }
    connections: {
      redis: {
        source: redis.id
      }
    }
  }
}

resource redis 'Applications.Datastores/redisCaches@2023-10-01-preview' = {
  name: 'redis'
  properties: {
    application: todolist.id
    environment: environment
  }
}
