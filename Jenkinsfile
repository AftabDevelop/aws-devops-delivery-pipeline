
pipeline {
    agent any

    environment {
        IMAGE_NAME      = 'aftab710/devops-app'
        IMAGE_TAG       = "${env.BUILD_NUMBER}"
        DOCKER_CREDS_ID = 'docker-hub-credentials'
    }

    stages {
        stage('Checkout') {
            steps {
                checkout scm
            }
        }

        stage('Build Docker image') {
            steps {
                dir('app') {
                    sh 'docker build -t ${IMAGE_NAME}:${IMAGE_TAG} .'
                }
            }
        }

        stage('Smoke test') {
            steps {
                sh '''
                    docker rm -f smoke-test || true
                    docker run -d --name smoke-test -p 3100:3000 ${IMAGE_NAME}:${IMAGE_TAG}
                    sleep 5
                    curl -f http://localhost:3100/health
                '''
            }
            post {
                always {
                    sh 'docker rm -f smoke-test || true'
                }
            }
        }

        stage('Push to Docker Hub') {
            steps {
                withCredentials([usernamePassword(
                    credentialsId: "${DOCKER_CREDS_ID}",
                    usernameVariable: 'DOCKER_USER',
                    passwordVariable: 'DOCKER_PASS'
                )]) {
                    sh '''
                        echo "$DOCKER_PASS" | docker login -u "$DOCKER_USER" --password-stdin
                        docker push ${IMAGE_NAME}:${IMAGE_TAG}
                        docker tag ${IMAGE_NAME}:${IMAGE_TAG} ${IMAGE_NAME}:latest
                        docker push ${IMAGE_NAME}:latest
                    '''
                }
            }
        }
    }

    post {
        always {
            sh 'docker logout || true'
        }
        success {
            echo "Build #${env.BUILD_NUMBER} succeeded: ${IMAGE_NAME}:${IMAGE_TAG} pushed to Docker Hub"
        }
        failure {
            echo 'Pipeline failed. Check the console output of the failing stage.'
        }
    }
}

