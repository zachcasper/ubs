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
      // env: {
      //   CONNECTION_POSTGRESQL_PASSWORD: {
      //     valueFrom: {
      //       secretRef: {
      //         key: 'username'
      //         source: credentials.id
      //       }
      //     }
      //   }
      // }
    }
    connections: {
      postgresql: {
        source: postgresql.id
        // disableDefaultEnvVars: true
      }
    }
  }
}

resource credentials 'Applications.Core/secretStores@2023-10-01-preview' = {
  name: 'credentials'
  properties: {
    application: todolist.id
    environment: environment
    type: 'generic'
    data: {
      username: {
        value: postgresql.properties.username
      }
      password: {
        value: postgresql.properties.password
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
