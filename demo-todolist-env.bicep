extension radius

@secure()
param gitToken string

@description('Registry CA Certificate')
@secure()
param registryCACert string

resource env 'Applications.Core/environments@2023-10-01-preview' = {
  name: 'demo-todolist'
  properties: {
    compute: {
      kind: 'kubernetes'
      namespace: 'demo'
    }
    // providers: {
    //   azure: {
    //     scope: '/subscriptions/<my-subscription-id>/resourceGroups/<my-resource-group-name>'
    //   }
    // }
    recipeConfig: {
      terraform: {
        authentication: {
          git: {
            pat: {
              'devcloud.ubs.net': {
                secret: gitSecretStore.id
              }
            }
          }
        }
      //   registry: {
      //     mirror: 'https://iac.devcloud.ubs.net/terraform/providers/mirror/'
      //     authentication: {
      //       token: {
      //         secret: mirrorTokenSecret.id
      //       }
      //     }
      //     tls: {
      //       skipVerify: true
      //       caCertificate: {
      //         source: registryTLSCerts.id
      //         key: 'server.crt'
      //       }
      //     }
      //   }
      //   version: {
      //     releasesArchiveUrl: 'https://it4it-nexus-tp-repo.swissbank.com/repository/proxy-bin-crossplatform-hashicorp-raw-oss-consul/terraform/1.9.6/terraform_1.9.6_linux_amd64.zip'
      //     tls: {
      //       skipVerify: true
      //     }
      //   }
      }
    }
    recipes: {
      'Applications.Datastores/redisCaches': {
        default: {
          templateKind: 'terraform'
          templatePath: 'git::https://github.com/zachcasper/ubs.git//recipes/kubernetes/redis'
          // tls: {
          //   skipVerify: true
          // }
        }
      }
      'Radius.Resources/postgreSQL': {
        default: {
          templateKind: 'terraform'
          templatePath: 'git::https://github.com/zachcasper/ubs.git//recipes/kubernetes/postgresql'
          // tls: {
          //   skipVerify: true
          // }
        }
      }
    }
  }
}

resource mirrorTokenSecret 'Applications.Core/secretStores@2023-10-01-preview' = {
  name: 'mirror-token-secret'
  properties: {
    resource: 'demo-env/mirror-token-secret'
    type: 'generic'
    data: {
      token: {
        value: gitToken
      }
    }
  }
}

resource gitSecretStore 'Applications.Core/secretStores@2023-10-01-preview' = {
  name: 'git-secret-store'
  properties: {
    resource: 'demo-env/git-secret-store'
    type: 'generic'
    data: {
      pat: {
        value: gitToken
      }
      username: {
        value: 'oauth2'
      }
    }
  }
}

resource registryTLSCerts 'Applications.Core/secretStores@2023-10-01-preview' = {
  name: 'registry-tls-certs'
  properties: {
    resource: 'demo-env/registry-tls-certs'
    type: 'generic'
    data: {
      'server.crt': {
        value: registryCACert
      }
    }
  }
}
