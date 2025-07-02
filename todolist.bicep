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
      postgresql: {
        source: postgresql.id
      }
    }
  }
}

resource postgresql 'Radius.Resources/postgreSQL@2023-10-01-preview' = {
  name: 'postgresql'
  properties: {
    application: todolist.id
    environment: environment
    size: 'S'
  }
}

resource gateway 'Applications.Core/gateways@2023-10-01-preview' = {
  name: 'gateway'
  properties: {
    application: todolist.id
    routes: [
      {
        path: '/'
        destination: 'http://frontend:3000'
      }
    ]
  }
}
