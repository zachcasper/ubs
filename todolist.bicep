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
      db:{
        source: db.id
      }
    }
  }
}

resource db 'Radius.Resources/postgreSQL@2025-07-02' = {
  name: 'db'
  properties: {
    application: todolist.id
    environment: environment
    database: 'todolist'
  }
}

resource gw 'Applications.Core/gateways@2023-10-01-preview' = {
  name: 'gw'
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
