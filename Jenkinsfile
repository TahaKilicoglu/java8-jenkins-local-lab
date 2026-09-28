pipeline {
  agent any
  options {
    skipDefaultCheckout()
    timestamps()
    disableConcurrentBuilds()
    timeout(time: 25, unit: 'MINUTES')
  }
  stages {
    stage('Checkout GitHub main') {
      steps {
        checkout scm
        sh 'git log -1 --format="commit=%h author=%an subject=%s"'
      }
    }
    stage('Build and verify with Java 8') {
      steps {
        script { env.IMAGE_REF = "loadtest-order:${sh(script: 'git rev-parse --short=12 HEAD', returnStdout: true).trim()}-${env.BUILD_NUMBER}" }
        sh 'docker build -t "$IMAGE_REF" .'
      }
    }
    stage('Deploy on local Docker') {
      steps {
        withCredentials([usernamePassword(credentialsId: 'orders-db-app', usernameVariable: 'DB_USER', passwordVariable: 'DB_PASSWORD')]) {
          sh '''#!/bin/sh
set -eu
set +x
sh scripts/local-deploy.sh "$IMAGE_REF"
'''
        }
      }
    }
    stage('Smoke check') {
      steps {
        sh '''#!/bin/sh
set -eu
curl -fsS http://order:8080/api/orders/ping
echo
docker inspect --format='running image={{.Config.Image}}' loadtest-order
'''
      }
    }
  }
  post {
    failure {
      sh 'docker logs --tail=60 loadtest-order 2>/dev/null || true'
    }
  }
}
