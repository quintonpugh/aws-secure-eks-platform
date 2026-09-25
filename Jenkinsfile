pipeline {
    agent any

    options {
        skipDefaultCheckout(true)
    }

    environment {
        AWS_REGION     = 'us-east-1'
        CLUSTER_NAME   = 'secure-eks-dev-cluster'
        APP_NAME       = 'secure-eks-demo'
        ECR_REPOSITORY = 'secure-eks-dev-app'
        K8S_NAMESPACE  = 'default'
        KUBECONFIG     = "${WORKSPACE}/.kube/config"
    }

    stages {
        stage('Checkout') {
            steps {
                checkout scm
            }
        }

        stage('Test Application') {
            steps {
                sh '''
                    python3 -m py_compile app/app.py
                    echo "Application syntax validation passed."
                '''
            }
        }

        stage('AWS Identity') {
            steps {
                sh '''
                    aws sts get-caller-identity
                '''
            }
        }

        stage('Build Image') {
            steps {
                sh '''
                    ACCOUNT_ID=$(aws sts get-caller-identity \
                      --query Account \
                      --output text)

                    ECR_REGISTRY="${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
                    IMAGE_TAG="build-${BUILD_NUMBER}"

                    echo "${ECR_REGISTRY}/${ECR_REPOSITORY}:${IMAGE_TAG}" \
                      > .image-uri

                    docker build \
                      -t "${ECR_REPOSITORY}:${IMAGE_TAG}" \
                      app/
                '''
            }
        }

        stage('Push to ECR') {
            steps {
                sh '''
                    ACCOUNT_ID=$(aws sts get-caller-identity \
                      --query Account \
                      --output text)

                    ECR_REGISTRY="${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
                    IMAGE_TAG="build-${BUILD_NUMBER}"

                    aws ecr get-login-password \
                      --region "$AWS_REGION" |
                      docker login \
                        --username AWS \
                        --password-stdin "$ECR_REGISTRY"

                    docker tag \
                      "${ECR_REPOSITORY}:${IMAGE_TAG}" \
                      "${ECR_REGISTRY}/${ECR_REPOSITORY}:${IMAGE_TAG}"

                    docker push \
                      "${ECR_REGISTRY}/${ECR_REPOSITORY}:${IMAGE_TAG}"
                '''
            }
        }

        stage('EKS Authentication') {
            steps {
                sh '''
                    mkdir -p "$(dirname "$KUBECONFIG")"

                    aws eks update-kubeconfig \
                      --region "$AWS_REGION" \
                      --name "$CLUSTER_NAME" \
                      --kubeconfig "$KUBECONFIG"

                    kubectl auth can-i patch deployments \
                      --namespace "$K8S_NAMESPACE"
                '''
            }
        }

        stage('Render Manifest') {
            steps {
                sh '''
                    IMAGE_URI=$(cat .image-uri)

                    sed "s|ECR_IMAGE_PLACEHOLDER|${IMAGE_URI}|g" \
                      kubernetes/deployment.yaml \
                      > rendered-deployment.yaml

                    echo "Deployment manifest rendered."
                    grep "image:" rendered-deployment.yaml
                '''
            }
        }

        stage('Deploy to EKS') {
            steps {
                sh '''
                    kubectl apply \
                      -f kubernetes/service.yaml \
                      --namespace "$K8S_NAMESPACE"

                    kubectl apply \
                      -f rendered-deployment.yaml \
                      --namespace "$K8S_NAMESPACE"

                    kubectl rollout status \
                      deployment/"$APP_NAME" \
                      --namespace "$K8S_NAMESPACE" \
                      --timeout=180s

                    echo "Deployment rollout completed."

                    kubectl get deployment "$APP_NAME" \
                      --namespace "$K8S_NAMESPACE"

                    kubectl get pods \
                      --namespace "$K8S_NAMESPACE" \
                      -l app="$APP_NAME"

                    kubectl get service "$APP_NAME" \
                      --namespace "$K8S_NAMESPACE"
                '''
            }
        }
    }

    post {
        always {
            sh 'docker logout || true'
        }
    }
}
